defmodule Fude.Components do
  @moduledoc """
  The function component of Fude: `<.chart>`.

      import Fude.Components

      <.chart id="revenue" chart={Fude.bar(@sales, x: :region, y: :revenue)} />

  A saved spec draws with its data given again:

      <.chart id="revenue" spec={@report.chart} data={@sales} />

  The chart needs the `Fude` hook in the LiveSocket and the Fude CSS (see
  the README). The server writes the chart's title, its words, a single
  number (`Fude.number/2`) and a table of the data; the hook draws the
  plot, and draws it again in place when the chart or its data change,
  moving its marks to their new places.

  Before the hook mounts (and with JavaScript off), the chart is its words
  and its table.

  A chart that cannot draw (a field that is not in the data, a spec that
  is not valid) shows why, in place of the plot, and does not raise.
  """

  use Phoenix.Component

  alias Fude.{Chart, Compile, Spec}

  @doc """
  Renders a chart.

  Give it a chart (`chart`, from the functions of `Fude`), or a spec
  (`spec`, from `Fude.Spec.dump/1`) with its data (`data`).
  """
  attr :id, :string, required: true, doc: "the id of the chart, unique on the page"
  attr :chart, Chart, default: nil, doc: "the chart, from the functions of `Fude`"
  attr :spec, :map, default: nil, doc: "a spec of the chart (`Fude.Spec.dump/1`), with `data`"

  attr :data, :any,
    default: nil,
    doc:
      "the chart's data, for a spec or a chart made without it; a map of names for a chart of several"

  attr :height, :integer,
    default: nil,
    doc: "the height of the plot in pixels; the chart's own, or 320"

  attr :locale, :string,
    default: nil,
    doc: "the locale that writes numbers and dates; the browser's unless given"

  attr :table, :boolean,
    default: true,
    doc: "whether the data table is on the page (under a toggle)"

  attr :class, :any, default: nil, doc: "classes for the chart's element"
  attr :rest, :global

  def chart(assigns) do
    assigns = prepare(assigns)

    ~H"""
    <figure
      id={@id}
      class={["fude", "fude-kind-#{@kind}", @class]}
      phx-hook="Fude"
      data-fude={@config}
      aria-labelledby={@wire["title"] && "#{@id}-title"}
      {@rest}
    >
      <figcaption :if={@wire["title"] || @wire["subtitle"]} class="fude-head">
        <span :if={@wire["title"]} id={"#{@id}-title"} class="fude-title">{@wire["title"]}</span>
        <span :if={@wire["subtitle"]} class="fude-subtitle">{@wire["subtitle"]}</span>
      </figcaption>
      <p :if={@errors != []} class="fude-error" role="alert">
        {Enum.join(@errors, ". ")}
      </p>
      <.single :if={@wire["single"]} id={@id} single={@wire["single"]} kind={@kind} />
      <div
        :if={@errors == [] and @wire["layers"]}
        id={"#{@id}-plot"}
        class="fude-plot"
        style={"height: #{@plot_height}px"}
        role="img"
        aria-label={@wire["description"]}
        phx-update="ignore"
      >
      </div>
      <details :if={@table and @rows != []} class="fude-data">
        <summary>Data</summary>
        <table>
          <thead>
            <tr><th :for={head <- @heads} scope="col">{head}</th></tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows}><td :for={cell <- row}>{plain(cell)}</td></tr>
          </tbody>
        </table>
      </details>
      <p :if={@wire["caption"] || @wire["source"]} class="fude-foot">
        <span :if={@wire["caption"]} class="fude-caption">{@wire["caption"]}</span>
        <span :if={@wire["source"]} class="fude-source">{@wire["source"]}</span>
      </p>
    </figure>
    """
  end

  attr :id, :string, required: true
  attr :single, :map, required: true
  attr :kind, :string, required: true

  defp single(%{kind: "gauge"} = assigns) do
    assigns = assign(assigns, :gauge, gauge(assigns.single))

    ~H"""
    <div
      class="fude-single fude-gauge"
      role="meter"
      aria-valuemin={@single["min"]}
      aria-valuemax={@single["max"]}
      aria-valuenow={@single["value"]}
      aria-label={@single["label"]}
    >
      <svg viewBox="0 0 200 112" aria-hidden="true">
        <path class="fude-gauge-track" d={@gauge.track} />
        <path :if={@gauge.value} class="fude-gauge-value" d={@gauge.value} />
        <line
          :if={@gauge.target}
          class="fude-gauge-target"
          x1={elem(@gauge.target, 0)}
          y1={elem(@gauge.target, 1)}
          x2={elem(@gauge.target, 2)}
          y2={elem(@gauge.target, 3)}
        />
      </svg>
      <data class="fude-value" value={plain(@single["value"])} data-format={@single["format"]}>
        {plain(@single["value"]) || "—"}
      </data>
      <span :if={@single["label"]} class="fude-label">{@single["label"]}</span>
    </div>
    """
  end

  defp single(assigns) do
    ~H"""
    <div class="fude-single">
      <data class="fude-value" value={plain(@single["value"])} data-format={@single["format"]}>
        {plain(@single["value"]) || "—"}
      </data>
      <span :if={@single["label"]} class="fude-label">{@single["label"]}</span>
      <span
        :if={@kind == "trend" and change(@single) != nil}
        class={["fude-delta", if(change(@single) >= 0, do: "fude-up", else: "fude-down")]}
      >
        <data value={change(@single)} data-format="percent-change">{percent(change(@single))}</data>
      </span>
      <div
        :if={@kind == "progress"}
        class="fude-progress"
        role="progressbar"
        aria-valuemin="0"
        aria-valuemax={@single["goal"]}
        aria-valuenow={@single["value"]}
        aria-label={@single["label"]}
      >
        <span style={"width: #{share(@single)}%"}></span>
      </div>
    </div>
    """
  end

  defp prepare(assigns) do
    {wire, errors} = compile(assigns)
    {heads, rows} = if errors == [] and assigns.table, do: Compile.table(wire), else: {[], []}

    config =
      wire
      |> Map.put("locale", assigns.locale)
      |> Map.put("id", assigns.id)
      |> JSON.encode!()

    assigns
    |> assign(
      wire: wire,
      errors: errors,
      config: config,
      kind: wire["kind"] || "chart",
      plot_height: assigns.height || wire["height"] || default_height(wire["kind"]),
      heads: heads,
      rows: rows
    )
  end

  defp default_height("sparkline"), do: 48
  defp default_height(_kind), do: 320

  defp compile(%{chart: %Chart{} = chart, data: data}) do
    result(chart, Compile.compile(chart, datasets(chart, data)))
  end

  defp compile(%{spec: spec, data: data}) when is_map(spec) do
    case Spec.load(spec) do
      {:ok, chart} ->
        result(chart, Compile.compile(chart, datasets(chart, data)))

      {:error, errors} ->
        {%{"v" => 1},
         ["The chart's spec is not valid: " <> String.trim(Spec.format_errors(errors))]}
    end
  end

  defp compile(%{id: id}) do
    raise ArgumentError, "<.chart id=#{inspect(id)}> needs a chart or a spec"
  end

  defp result(_chart, {:ok, wire}), do: {wire, []}

  defp result(chart, {:error, errors}),
    do:
      {%{"v" => 1, "kind" => Atom.to_string(Chart.kind(chart) || :chart), "title" => chart.title},
       errors}

  # The data given to the component: the chart's own data, or a map of
  # names for a chart of several datasets.
  defp datasets(_chart, nil), do: %{}

  defp datasets(%Chart{data: name}, data) when is_map(data) and not is_struct(data) do
    if Map.has_key?(data, :columns) or Map.has_key?(data, "columns"),
      do: %{name => data},
      else: Map.new(data, fn {key, value} -> {to_string(key), value} end)
  end

  defp datasets(%Chart{data: name}, data), do: %{name => data}

  # The arcs of a gauge, from the left over the top to the right: its track,
  # its value, and a tick at its target.
  @cx 100
  @cy 100
  @r 80

  defp gauge(%{"value" => value, "min" => min, "max" => max} = single) do
    share = fn v -> if is_number(v) and max > min, do: min(1, max(0, (v - min) / (max - min))) end
    value = share.(value)
    target = share.(single["target"])

    %{
      track: arc(0, 1),
      value: if(value && value > 0, do: arc(0, value)),
      target: if(target, do: tick(target))
    }
  end

  defp arc(from, to) do
    {x0, y0} = at(from, @r)
    {x1, y1} = at(to, @r)
    "M#{x0} #{y0} A#{@r} #{@r} 0 0 1 #{x1} #{y1}"
  end

  defp tick(t) do
    {x0, y0} = at(t, @r - 14)
    {x1, y1} = at(t, @r + 14)
    {x0, y0, x1, y1}
  end

  defp at(t, r) do
    angle = :math.pi() * (1 - t)
    {Float.round(@cx + r * :math.cos(angle), 2), Float.round(@cy - r * :math.sin(angle), 2)}
  end

  defp change(%{"value" => value, "compare" => compare})
       when is_number(value) and is_number(compare) and compare != 0,
       do: (value - compare) / abs(compare)

  defp change(_single), do: nil

  defp percent(change), do: "#{if change >= 0, do: "+", else: ""}#{Float.round(change * 100, 1)}%"

  defp share(%{"value" => value, "goal" => goal})
       when is_number(value) and is_number(goal) and goal > 0,
       do: (value / goal * 100) |> min(100) |> max(0) |> Float.round(2)

  defp share(_single), do: 0

  defp plain(nil), do: nil
  defp plain(value) when is_float(value), do: :erlang.float_to_binary(value, [:short])
  defp plain(%Date{} = date), do: Date.to_iso8601(date)
  defp plain(%DateTime{} = time), do: DateTime.to_iso8601(time)
  defp plain(value), do: to_string(value)
end
