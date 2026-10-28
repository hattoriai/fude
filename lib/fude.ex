defmodule Fude do
  @moduledoc """
  Fude (筆, "brush") draws charts in a Phoenix app.

      Fude.bar(sales, x: :region, y: :revenue)
      Fude.line(visits, x: :day, y: :count, color: :source)
      Fude.histogram(orders, x: :total, bins: 30)
      Fude.number(totals, value: :mrr, format: :compact, label: "MRR")

  Each function takes the data and the chart's channels and options, and
  gives a `Fude.Chart`, which `<.chart>` draws (`Fude.Components`):

      <.chart id="revenue" chart={Fude.bar(@sales, x: :region, y: :revenue)} />

  The data is a list of maps or a map of `:columns` and `:rows` (as a
  query result has them). A channel is a field, or a field with what to
  do with it (`{:sum, :revenue}`, `{:month, :created_at}`, see
  `Fude.Channel`).

  Every function also takes the keys of the chart:

    * `:title`, `:subtitle` - above the chart.
    * `:caption`, `:source` - below it, as a graphics desk sets them.
    * `:description` - what a screen reader says of the chart; Fude writes
      one when it is not given.
    * `:height` - the height of the plot in pixels.
    * `:data` - the name of the chart's data in its spec, `"data"` when
      not given (see `Fude.Spec`).
    * `:brush` - what dragging across the x axis does: `:zoom` (the chart
      zooms to the range in place), `:select` (the range goes to the
      server, see `Fude.Live.brush_range/1`) or `false` (the default).

  A chart is plain data: `Fude.Spec.dump/1` gives a map to save, and
  `Fude.Spec.load/1` takes it back.

  ## Layers

  Charts drawn one over the other share their axes:

      Fude.layers(visits, [
        Fude.area(x: :day, y: :count),
        Fude.line(x: :day, y: :count),
        Fude.rule(y: 1000, label: "Goal")
      ])
  """

  alias Fude.{Chart, Layer}

  @doc "Fude's version."
  @spec version() :: String.t()
  def version, do: unquote(Mix.Project.config()[:version])

  @kinds [
    bar: "Bars: a category on `x` and a number on `y`; `horizontal: true` turns them.",
    line: "Lines: a time or a number on `x`, a number on `y`, a line for each `color`.",
    area: "Areas: as lines, filled down to zero; stacked when they have a `color`.",
    scatter:
      "Points at `x` and `y`, colored by `color` and sized by `size`; `connect: true` joins the points of each category (a dumbbell), `labels: true` writes their values.",
    bubble:
      "Points at `x` and `y`, sized by `size`; `connect: true` joins the points of each category, `labels: true` writes their values.",
    pie: "A pie: a slice for each `color`, as large as its `value`.",
    donut: "A donut: a pie with a hole (`inner`, the hole's share of the radius).",
    histogram: "A histogram: the numbers of `x` counted in bins (`bins`, about how many).",
    heatmap: "A heatmap: a cell for each `x` and `y`, colored by `color`.",
    rule: "A rule across the chart at `x` or at `y`, with a `label`.",
    text:
      "Text at `x` and `y`; with a category on `y` and no `x`, a column at the right of the plot, beside each category.",
    sparkline: "A small line with no axes, for a table or a card.",
    number: "One number, large, with a `label`.",
    trend: "One number with its change from `compare`, and its history (`spark`).",
    progress: "One number on a bar towards a `goal`.",
    waterfall:
      "A waterfall: how each change of `y` (a step on `x`) moves a running total; `total` adds a bar of the end, `start` names the first bar as a total.",
    funnel: "A funnel: the stages on `x` with their `y`, each with its share of the first.",
    gauge:
      "One number on an arc from `min` to `max` (0 and 100 when not given), with a `target`.",
    choropleth:
      "A map of regions colored by `color`: each `region` an ISO code (`\"PRT\"`, `\"PT\"`), a number code or a name; `map` is `\"world\"` (the default) or `\"us-states\"`.",
    bubble_map: "A map with a circle at each `region`, sized by `size`."
  ]

  for {kind, doc} <- @kinds do
    @doc """
    #{doc}

        Fude.#{kind}(data, ...)
        Fude.#{kind}(...)          # a layer, for Fude.layers/2
    """
    @spec unquote(kind)(term(), keyword()) :: Chart.t()
    def unquote(kind)(data, opts), do: chart(unquote(kind), data, opts)

    @spec unquote(kind)(keyword() | term()) :: Chart.t()
    def unquote(kind)(opts_or_data) do
      if keyword?(opts_or_data),
        do: chart(unquote(kind), nil, opts_or_data),
        else: chart(unquote(kind), opts_or_data, [])
    end
  end

  @doc """
  A chart of layers drawn one over the other, on the same axes: the first
  at the back. Each layer is a chart of one kind, made without data; the
  layers read the same data.
  """
  @spec layers(term(), [Chart.t()], keyword()) :: Chart.t()
  def layers(data, charts, opts \\ []) when is_list(charts) do
    {chart_opts, rest} = Chart.split(opts)

    unless rest == [] do
      raise ArgumentError, "Fude.layers/3 takes only the keys of a chart, got: #{inspect(rest)}"
    end

    layers = Enum.flat_map(charts, fn %Chart{layers: layers} -> layers end)

    %Chart{layers: layers}
    |> Chart.put(chart_opts)
    |> put_data(data)
  end

  @doc """
  Writes a note on the chart, at a place of its data (see
  `Fude.Annotation`):

      chart
      |> Fude.annotate(:label, x: "North", y: 136_000, text: "Best quarter on record")
      |> Fude.annotate(:band, x: {~D[2026-03-01], ~D[2026-05-01]}, text: "Launch")
      |> Fude.annotate(:line, y: 4000, text: "Goal")
  """
  @spec annotate(Chart.t(), Fude.Annotation.type(), keyword()) :: Chart.t()
  def annotate(%Chart{} = chart, type, opts) do
    %{chart | annotations: chart.annotations ++ [Fude.Annotation.new(type, opts)]}
  end

  @doc """
  Small multiples: the chart drawn once for each value of a field, side
  by side, on the same scales, so that the panels compare at a glance.

      Fude.line(sales, x: :month, y: :revenue)
      |> Fude.facet(:region, columns: 3)

  `columns` is how many panels make a row; as many as fit when not given.
  """
  @spec facet(Chart.t(), atom() | String.t(), keyword()) :: Chart.t()
  def facet(%Chart{} = chart, field, opts \\ []) when is_atom(field) or is_binary(field) do
    columns = Keyword.get(opts, :columns)

    unless is_nil(columns) or (is_integer(columns) and columns > 0) do
      raise ArgumentError, "Fude: :columns of a facet is a whole number, got: #{inspect(columns)}"
    end

    %{chart | facet: %{field: to_string(field), columns: columns}}
  end

  if Code.ensure_loaded?(Ecto.Query) do
    @doc """
    The data of an Ecto query or schema, grouped and aggregated in the
    database when the chart draws (see `Fude.Query`):

        Order |> Fude.query(Repo) |> Fude.bar(x: :status, y: {:count, :id})
    """
    @spec query(Ecto.Queryable.t(), module(), keyword()) :: Fude.Query.t()
    def query(queryable, repo, opts \\ []), do: Fude.Query.new(queryable, repo, opts)
  end

  @doc "Sets the chart's title, and with `:subtitle`, its subtitle."
  @spec title(Chart.t(), String.t(), keyword()) :: Chart.t()
  def title(%Chart{} = chart, title, opts \\ []) do
    Chart.put(chart, [title: title] ++ Keyword.take(opts, [:subtitle]))
  end

  @doc """
  Gives the chart its data, under its data's name. A chart loaded from a
  spec gets its data again this way, or from `<.chart data={...}>`.
  """
  @spec put_data(Chart.t(), term()) :: Chart.t()
  def put_data(%Chart{} = chart, nil), do: chart
  def put_data(%Chart{} = chart, data), do: put_data(chart, chart.data, data)

  @doc "Gives the chart a dataset of a name, for a layer that reads it."
  @spec put_data(Chart.t(), String.t(), term()) :: Chart.t()
  def put_data(%Chart{} = chart, name, data),
    do: %{chart | datasets: Map.put(chart.datasets, to_string(name), data)}

  @doc """
  The chart as Markdown, for where the hook does not draw (a document's
  copy, an agent that reads it): its words and its data as a table. See
  `Fude.Export`.

      Fude.bar(sales, x: :region, y: :revenue, title: "Revenue") |> Fude.to_markdown()
  """
  @spec to_markdown(Fude.Export.chart(), term()) :: String.t()
  defdelegate to_markdown(chart, data \\ nil), to: Fude.Export

  @doc "The chart as plain text: its words and its data by tabs. See `Fude.Export`."
  @spec to_text(Fude.Export.chart(), term()) :: String.t()
  defdelegate to_text(chart, data \\ nil), to: Fude.Export

  @doc "The chart as HTML for a page with no LiveView: its words and a table. See `Fude.Export`."
  @spec to_html(Fude.Export.chart(), term()) :: Phoenix.HTML.safe()
  defdelegate to_html(chart, data \\ nil), to: Fude.Export

  defp chart(kind, data, opts) do
    {chart_opts, layer_opts} = Chart.split(opts)

    %Chart{layers: [Layer.new(kind, layer_opts)]}
    |> Chart.put(chart_opts)
    |> put_data(data)
  end

  defp keyword?([{key, _} | _] = list) when is_atom(key), do: Keyword.keyword?(list)
  defp keyword?(_), do: false
end
