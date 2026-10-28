if Code.ensure_loaded?(Issho.Tool) do
  defmodule Fude.Issho.Tools.Read do
    @moduledoc false
    use Issho.Tool,
      name: "read_chart",
      description: """
      Reads a chart of the room as its people see it: its spec (Fude's,
      with an "id" for each layer and annotation), and, when the app gives
      it, what it shows: its kind, its words, a description, and the table
      of its data, as the chart draws it (summed, by month...).
      """,
      annotations: [read_only: true, idempotent: true]

    arg(:room, :string, required: true)
    arg(:chart, :string, description: "The chart's document; the room itself unless given")
    arg(:rows, :integer, min: 0, max: 1000, description: "The most rows of the table (50)")

    alias Issho.Tool.Context

    @impl true
    def call(args, ctx) do
      case Context.open(ctx, args.room, args[:chart]) do
        {:ok, _participant, document, %{"engine" => "map"} = snapshot} ->
          state = snapshot["state"]

          {:ok,
           %{
             "chart" => document,
             "revision" => snapshot["revision"],
             "spec" => state,
             "shows" => shows(state, document, ctx, Map.get(args, :rows, 50))
           }}

        {:ok, _participant, document, _snapshot} ->
          {:error, "#{document} is not a chart."}

        {:error, reason} ->
          Context.error(reason)
      end
    end

    defp shows(state, document, ctx, count) do
      with {:ok, chart} <- Fude.Issho.chart(state),
           {:ok, data} <- Fude.Issho.data(document, ctx),
           {:ok, wire} <- Fude.Compile.compile(chart, %{chart.data => data}) do
        {heads, rows} = Fude.Compile.table(wire)

        %{
          "kind" => wire["kind"],
          "title" => wire["title"],
          "subtitle" => wire["subtitle"],
          "description" => wire["description"],
          "columns" => heads,
          "rows" => rows |> Enum.take(count) |> Enum.map(fn row -> Enum.map(row, &plain/1) end),
          "row_count" => length(rows)
        }
      else
        :none -> "The app does not give agents this chart's data; the spec names it."
        {:error, [_ | _] = errors} -> %{"errors" => errors}
        {:error, reason} -> %{"errors" => [reason]}
      end
    end

    defp plain(%Date{} = date), do: Date.to_iso8601(date)
    defp plain(%DateTime{} = time), do: DateTime.to_iso8601(time)
    defp plain(%NaiveDateTime{} = time), do: NaiveDateTime.to_iso8601(time)
    defp plain(%_{} = struct), do: to_string(struct)
    defp plain(value), do: value
  end

  defmodule Fude.Issho.Tools.Change do
    @moduledoc false
    use Issho.Tool,
      name: "change_chart",
      description: """
      Changes a chart of the room: give its spec as you want it (read it
      with read_chart first), and only what you changed is sent, so that
      the others' changes at the same time stay. Keep the "id" of each
      layer and annotation you keep; one with no id is new. The spec must
      be a valid chart, or nothing changes and you get every error, with
      where it is.

      A spec is Fude's: {"fude": 1, "title": "...", "layers": [{"id":
      "l1", "kind": "bar", "x": "region", "y": {"field": "revenue",
      "aggregate": "sum"}, "color": "channel"}], "annotations": [{"type":
      "label", "x": "North", "y": 136000, "text": "Best quarter"}]}. The
      kinds: bar, line, area, scatter, bubble, pie, donut, histogram,
      heatmap, waterfall, funnel, timeline, boxplot, candlestick, treemap,
      radar, radial_bar, parliament, sparkline, choropleth, bubble_map, rule, text,
      number, trend, gauge, progress. A channel is a field's name, or
      {"field", "aggregate" (count, sum, mean, median, min, max, distinct),
      "time" (year, quarter, month, week, day, hour, minute), "bin",
      "format", "digits" (decimals, 0 to 20), "suffix" (words after each
      value: "×", "/s"), "scheme" (a color's: blue, green, orange, purple,
      gray, viridis, red_blue, red_green, categorical, okabe_ito, or a list
      of colors), "mid", "highlight" (a color's series that keep their colors, the
      others gray), "title", "sort", "stack"}. A scatter or a bubble
      may have "connect" (a line between the points of each category: a
      dumbbell) and "labels" (each point's value). A text layer with "y"
      and "text" and no "x" is a column at the right of the plot, beside
      each category. A tooltip's list may end with what it adds:
      {"change", "share", "rank", "history"}, each true or false. A chart
      may have "animate" (false, or {"duration": ms}), "frame" (a label for
      a sequence of renders) and "brush" ("zoom" or "select": what
      dragging across the x axis does).
      """,
      annotations: [destructive: true]

    arg(:room, :string, required: true)
    arg(:chart, :string, description: "The chart's document; the room itself unless given")
    arg(:spec, :any, required: true, description: "The chart's spec, as you want it")

    alias Issho.Tool.Context

    @impl true
    def call(%{spec: spec} = args, ctx) when is_map(spec) do
      with {:ok, participant, document, %{"engine" => "map"} = snapshot} <-
             Context.open(ctx, args.room, args[:chart]),
           {:ok, chart} <- Fude.Issho.chart(spec) do
        before = snapshot["state"]

        participant
        |> send_ops(
          document,
          Fude.Issho.ops(before, chart |> keep_ids(before) |> Fude.Issho.state())
        )
      else
        {:ok, _participant, document, _snapshot} -> {:error, "#{document} is not a chart."}
        {:error, reason} when is_binary(reason) -> {:error, reason}
        {:error, reason} -> Context.error(reason)
      end
    end

    def call(_args, _ctx), do: {:error, "The spec is a map: read_chart gives the chart's."}

    defp send_ops(_participant, _document, []), do: {:ok, "Nothing changed."}

    defp send_ops(participant, document, ops) do
      case Issho.Participant.transact(participant, document, ops) do
        {:ok, receipt} -> {:ok, %{"revision" => receipt["revision"], "changes" => length(ops)}}
        {:error, reason} -> Context.error(reason)
      end
    end

    # A layer or an annotation that the agent gave with no id is the one
    # at its place before, when that one's id is not given elsewhere: an
    # agent that rewrites a spec without its ids changes the layers it
    # had, rather than replacing them.
    defp keep_ids(chart, before) do
      %{
        chart
        | layers: keep(chart.layers, before["layers"]),
          annotations: keep(chart.annotations, before["annotations"])
      }
    end

    defp keep(items, before) when is_list(before) do
      given = items |> Enum.map(& &1.id) |> Enum.reject(&is_nil/1)

      items
      |> Enum.with_index()
      |> Enum.map(fn
        {%{id: nil} = item, index} ->
          adopt(item, Enum.at(before, index), given)

        {item, _index} ->
          item
      end)
    end

    defp keep(items, _before), do: items

    defp adopt(item, %{"id" => id}, given) when is_binary(id),
      do: if(id in given, do: item, else: %{item | id: id})

    defp adopt(item, _before, _given), do: item
  end
end
