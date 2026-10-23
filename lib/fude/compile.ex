defmodule Fude.Compile do
  @moduledoc false
  # A chart and its data, made into what the browser draws: for each layer
  # a mark and its columns (x, y, color...), and the chart's scales with
  # their domains. The kinds are made into marks here (a histogram is bars
  # over bins, a pie is arcs), so the browser knows only marks.
  #
  # Values go as the browser draws them: numbers, times in milliseconds,
  # and categories as their index in their scale's domain. The browser
  # widens the number domains to round ticks, as wide as it is
  # (Fude.Rules).

  alias Fude.{Channel, Chart, Data, Layer, Rules}

  @v 1

  @type result :: {:ok, map()} | {:error, [String.t()]}

  @spec compile(Chart.t(), map()) :: result()
  def compile(%Chart{} = chart, datasets \\ %{}) do
    datasets = Map.merge(chart.datasets, Map.new(datasets, fn {k, v} -> {to_string(k), v} end))
    data = datasets |> Map.get(chart.data) |> source(chart)

    with :ok <- check_fields(chart, data) do
      {:ok, build(chart, data)}
    end
  rescue
    # The errors of a chart that a person made (a spec): Fude's own.
    error in ArgumentError ->
      case Exception.message(error) do
        "Fude: " <> message -> {:error, [message]}
        _ -> reraise error, __STACKTRACE__
      end
  end

  # The data of a chart: its rows in columns, or a query that the database
  # aggregates (Fude.Query). Small multiples of a query read its rows.
  @query Fude.Query

  defp source(%{__struct__: @query} = query, %Chart{facet: nil}), do: query
  defp source(%{__struct__: @query} = query, chart), do: @query.data(query, fields(chart))
  defp source(data, chart), do: Data.new(data, fields(chart))

  # The fields that the chart reads.
  defp fields(%Chart{layers: layers, facet: facet}) do
    fields =
      for %Layer{channels: channels} <- layers,
          {_name, channel} <- channels,
          %Channel{field: field} <- List.wrap(channel),
          is_binary(field),
          uniq: true,
          do: field

    if facet, do: Enum.uniq([facet.field | fields]), else: fields
  end

  @doc false
  # Every field that a channel reads is in the data.
  def check_fields(%Chart{} = chart, %{__struct__: @query} = query) do
    case @query.names(query) do
      nil -> :ok
      names -> check_fields(chart, %Data{names: names})
    end
  end

  def check_fields(%Chart{layers: layers, facet: facet}, data) do
    names = Data.names(data)

    facet_errors =
      if facet && facet.field not in names,
        do: [
          "facet: the field #{inspect(facet.field)} is not in the data" <>
            Fude.Names.suggest(facet.field, names)
        ],
        else: []

    errors =
      for %Layer{channels: channels} <- layers,
          {name, channel} <- channels,
          channel <- List.wrap(channel),
          Channel.field?(channel),
          channel.field not in names,
          uniq: true do
        if names == [] do
          "#{name}: the chart has no data"
        else
          "#{name}: the field #{inspect(channel.field)} is not in the data" <>
            Fude.Names.suggest(channel.field, names)
        end
      end

    errors = facet_errors ++ errors
    if errors == [], do: :ok, else: {:error, Enum.uniq(errors)}
  end

  # Small multiples: the whole chart (its scales, its table, its words),
  # and a panel for each value of the facet's field, drawn on the whole
  # chart's scales.
  defp build(%Chart{facet: %{field: field} = facet} = chart, data) do
    whole = build(%{chart | facet: nil}, data)
    field_info = Data.field(data, field)

    values =
      data
      |> Data.column(field)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> sort_panels(field_info)

    tables =
      Enum.map(values, fn value ->
        {value, Enum.map(chart.layers, &table(&1, Data.where(data, field, value)))}
      end)

    scales =
      for {_value, layer_tables} <- tables, table <- layer_tables, reduce: %{} do
        acc -> merge_scales(acc, table.scales)
      end

    panels =
      Enum.map(tables, fn {value, layer_tables} ->
        %{
          "title" => panel_title(value, field_info),
          "layers" => Enum.map(layer_tables, &encode(&1, scales))
        }
      end)

    whole
    |> Map.put("scales", finish_scales(scales))
    |> Map.put("annotations", Enum.map(chart.annotations, &annotation(&1, scales)))
    |> Map.put("facet", %{
      "title" => Fude.Channel.title(%Fude.Channel{field: field}),
      "columns" => facet.columns,
      "panels" => panels
    })
  end

  defp build(chart, data) do
    single? = Chart.kind(chart) in [:number, :trend, :progress, :gauge]

    base = %{
      "v" => @v,
      "kind" => Atom.to_string(Chart.kind(chart)),
      "title" => chart.title,
      "subtitle" => chart.subtitle,
      "caption" => chart.caption,
      "source" => chart.source,
      "height" => chart.height
    }

    if single? do
      Map.put(base, "single", single(hd(chart.layers), data))
    else
      {layers, scales} = layers(chart.layers, data)

      base
      |> Map.put("layers", layers)
      |> Map.put("scales", finish_scales(scales))
      |> Map.put("axes", Chart.kind(chart) != :sparkline and not arcs?(chart))
      |> Map.put("description", chart.description || describe(chart, layers, scales))
      |> Map.put("annotations", Enum.map(chart.annotations, &annotation(&1, scales)))
    end
  end

  defp arcs?(chart),
    do: Enum.all?(chart.layers, &(&1.kind in [:pie, :donut, :choropleth, :bubble_map]))

  # -- Annotations -------------------------------------------------------------

  # An annotation with its places on the chart's scales: a category as its
  # index, a time in milliseconds; a place that is not on the chart is nil.
  defp annotation(%Fude.Annotation{} = a, scales) do
    {x, x2} = places(a.x, scales["x"])
    {y, y2} = places(a.y, scales["y"])

    %{
      "type" => Atom.to_string(a.type),
      "x" => x,
      "x2" => x2,
      "y" => y,
      "y2" => y2,
      "text" => a.text
    }
  end

  defp places({from, to}, scale), do: {place(from, scale), place(to, scale)}
  defp places(value, scale), do: {place(value, scale), nil}

  defp place(nil, _scale), do: nil
  defp place(_value, nil), do: nil

  defp place(value, %{"type" => type, "domain" => domain} = scale)
       when type in ["band", "point"] do
    value = if scale["time"], do: time(value), else: value
    Enum.find_index(domain, &(&1 == value or to_string(&1) == to_string(value)))
  end

  defp place(value, %{"type" => "time"}), do: time(value)
  defp place(value, _scale) when is_number(value), do: value
  defp place(_value, _scale), do: nil

  # A time of an annotation: milliseconds, from a date's or a time's text.
  defp time(value) when is_integer(value), do: value

  defp time(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> Data.value(date, :time)
      {:error, _} -> datetime(value)
    end
  end

  defp time(_value), do: nil

  defp datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} ->
        Data.value(time, :time)

      _ ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, time} -> Data.value(time, :time)
          _ -> nil
        end
    end
  end

  # -- Single values ---------------------------------------------------------

  defp single(%Layer{kind: kind, channels: channels, options: options}, data) do
    value = first_value(channels[:value], data)

    %{
      "value" => value,
      "label" => options[:label] || Channel.title(channels[:value]),
      "format" => format(channels[:value]),
      "compare" => if(kind == :trend, do: compare(channels[:compare], channels[:value], data)),
      "goal" => if(kind == :progress, do: options[:goal] || 100),
      "min" => if(kind == :gauge, do: options[:min] || 0),
      "max" => if(kind == :gauge, do: options[:max] || 100),
      "target" => options[:target],
      "align" => align(options)
    }
  end

  # A single value is centered in its box unless it says otherwise.
  defp align(%{align: align}), do: Atom.to_string(align)
  defp align(_options), do: "center"

  defp first_value(%Channel{value: value}, _data) when not is_nil(value), do: value

  defp first_value(%Channel{aggregate: aggregate, field: field}, data)
       when not is_nil(aggregate) do
    aggregate(aggregate, Data.column(data, field))
  end

  defp first_value(%Channel{field: field}, data), do: data |> Data.column(field) |> List.first()

  # A trend compares with a field of the first row, or with the value of
  # the second row (the period before).
  defp compare(%Channel{} = channel, _value, data), do: first_value(channel, data)

  defp compare(nil, %Channel{field: field}, data) when is_binary(field),
    do: data |> Data.column(field) |> Enum.at(1)

  defp compare(nil, _value, _data), do: nil

  # -- Layers ------------------------------------------------------------------

  # Each layer's table, then the scales of all the layers together, then
  # the columns of each layer as the scales encode them. A layer whose y is
  # on the right axis has a y scale of its own, "yRight".
  defp layers(layers, data) do
    tables = layers |> Enum.map(&table(&1, data)) |> Enum.map(&right_axis/1)
    scales = Enum.reduce(tables, %{}, &merge_scales(&2, &1.scales))
    {Enum.map(tables, &encode(&1, scales)), scales}
  end

  defp right_axis(%{layer: %Layer{channels: %{y: %Channel{axis: :right}}}} = table) do
    case Map.pop(table.scales, "y") do
      {nil, _scales} -> table
      {y, scales} -> %{table | scales: Map.put(scales, "yRight", y)} |> Map.put(:axis, :right)
    end
  end

  defp right_axis(table), do: table

  defp sort_panels(values, %{type: :time}), do: Enum.sort(values)
  defp sort_panels(values, _field), do: values

  defp panel_title(value, %{type: :time, unit: unit}) when unit in [:day, :month, :year],
    do:
      value
      |> Integer.floor_div(86_400_000)
      |> then(&Date.add(~D[1970-01-01], &1))
      |> Date.to_iso8601()

  defp panel_title(value, %{type: :time}),
    do: value |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601()

  defp panel_title(value, _field) when is_float(value),
    do: :erlang.float_to_binary(value, [:short])

  defp panel_title(value, _field), do: to_string(value)

  # The marks of each kind, and how its channels go to the mark's.
  defp table(%Layer{kind: kind} = layer, %{__struct__: @query} = query) do
    layer = normalize(layer)
    channels = layer.channels |> Map.delete(:tooltip) |> Map.to_list()
    aggregated = aggregated(kind, channels)

    # The fields of a tooltip are read with the data, not pushed down: a
    # group takes the first of a field that is not a number.
    if @query.pushable?(aggregated) and not Map.has_key?(layer.channels, :tooltip) do
      {rows, bins, data} = @query.rows(query, channels, aggregated, &bins_of/3)
      marks(kind, layer, %{rows: rows, bins: bins}, data)
    else
      fields =
        for {_name, %Channel{field: field}} <- channels ++ tips(layer),
            is_binary(field),
            uniq: true,
            do: field

      table(layer, @query.data(query, fields))
    end
  end

  defp table(%Layer{kind: kind} = layer, data) do
    layer = layer |> normalize() |> type_tips(data)
    rows = rows(layer, data)
    marks(kind, layer, rows, data)
  end

  # Defaults of the kinds: the histogram's bins, a count for a bar or a
  # histogram with no y.
  defp normalize(%Layer{kind: :histogram, channels: channels, options: options} = layer) do
    x = %{channels.x | bin: channels.x.bin || %{count: options[:bins] || 20}}

    %{
      layer
      | channels: Map.merge(channels, %{x: x, y: %Channel{aggregate: :count, title: "Count"}})
    }
  end

  defp normalize(layer), do: layer

  # The fields of a layer's tooltip, as channels of the rows: each under
  # {:tooltip, index}, a name no channel has.
  defp tips(%Layer{channels: channels}) do
    channels
    |> Map.get(:tooltip, [])
    |> Enum.with_index(fn channel, i -> {{:tooltip, i}, channel} end)
  end

  # Each field of the tooltip with its type, so that a time is written as
  # one.
  defp type_tips(%Layer{channels: %{tooltip: tips} = channels} = layer, data) do
    tips = Enum.map(tips, &%{&1 | type: &1.type || x_type(&1, data)})
    %{layer | channels: %{channels | tooltip: tips}}
  end

  defp type_tips(layer, _data), do: layer

  # The rows of a layer: the data with each channel's value, its time
  # unit taken and its bin found, then grouped by the channels that are
  # not aggregated, with the others aggregated. A bar or an area sums the
  # values of a group when its channel has no aggregate, so that a bar is
  # one bar.
  defp rows(%Layer{kind: kind, channels: channels} = layer, data) do
    channels = channels |> Map.delete(:tooltip) |> Map.to_list()

    bins =
      Map.new(for {name, %Channel{bin: bin} = c} <- channels, bin, do: {name, bin_spec(c, data)})

    aggregated = aggregated(kind, channels)
    tips = tips(layer)
    aggregated = Map.merge(aggregated, tip_aggregates(tips, aggregated, data))
    channels = channels ++ tips

    rows =
      cond do
        constants?(channels) ->
          [Map.new(channels, fn {name, channel} -> {name, channel.value} end)]

        aggregated == %{} ->
          names = Enum.map(channels, &elem(&1, 0))

          channels
          |> Enum.map(fn {name, channel} -> column(channel, data, bins[name]) end)
          |> Enum.zip_with(&(names |> Enum.zip(&1) |> Map.new()))

        true ->
          group(channels, data, bins, aggregated)
      end

    %{rows: rows, bins: bins}
  end

  # A layer of constants only (a rule at y: 1000) is one row.
  defp constants?(channels),
    do: Enum.all?(channels, fn {_name, c} -> is_nil(c.field) and c.aggregate != :count end)

  # The channels that are aggregated, and how: by their own aggregate, or by
  # a sum for the value of a bar, an area, a cell or a slice.
  defp aggregated(kind, channels) do
    implicit =
      if kind in [:bar, :area, :heatmap, :pie, :donut, :choropleth, :bubble_map], do: :sum

    for {name, %Channel{} = channel} <- channels,
        fun = channel.aggregate || implicit_aggregate(implicit, kind, name, channel),
        into: %{},
        do: {name, fun}
  end

  # How a group of rows takes the fields of its tooltip: by their own
  # aggregate, else a sum of numbers and the first of anything else. Rows
  # that are not grouped keep their values.
  defp tip_aggregates(_tips, aggregated, _data) when aggregated == %{}, do: %{}

  defp tip_aggregates(tips, _aggregated, data) do
    Map.new(tips, fn {name, channel} ->
      fun =
        cond do
          channel.aggregate -> channel.aggregate
          channel.field && x_type(channel, data) == :number -> :sum
          true -> :first
        end

      {name, fun}
    end)
  end

  defp implicit_aggregate(nil, _kind, _name, _channel), do: nil

  defp implicit_aggregate(implicit, kind, name, %Channel{field: field, bin: bin}) do
    if name in value_channels(kind) and field != nil and !bin, do: implicit
  end

  # The rows grouped by the channels that are not aggregated, each group one
  # row with the aggregates of the others, in the order of its first row
  # (the order of the query). One pass over the columns, with a running
  # aggregate for each group: no map is made for a row.
  defp group(channels, data, bins, aggregated) do
    {keys, aggs} =
      Enum.split_with(channels, fn {name, _} -> not Map.has_key?(aggregated, name) end)

    key_names = Enum.map(keys, &elem(&1, 0))
    funs = Enum.map(aggs, fn {name, _} -> {name, Map.fetch!(aggregated, name)} end)

    key_tuples = tuples(keys, data, bins)
    value_tuples = tuples(aggs, data, bins)
    start = funs |> Enum.map(fn {_name, fun} -> start(fun) end) |> List.to_tuple()

    {groups, _index} =
      key_tuples
      |> Enum.zip(value_tuples)
      |> Enum.reduce({%{}, 0}, fn {key, values}, {groups, index} ->
        groups =
          case groups do
            %{^key => {first, acc}} -> %{groups | key => {first, step(funs, acc, values)}}
            _ -> Map.put(groups, key, {index, step(funs, start, values)})
          end

        {groups, index + 1}
      end)

    groups
    |> Enum.sort_by(fn {_key, {first, _acc}} -> first end)
    |> Enum.map(fn {key, {_first, acc}} ->
      key_names
      |> Enum.zip(Tuple.to_list(key))
      |> Map.new()
      |> Map.merge(finish(funs, acc))
    end)
  end

  # The values of channels as one tuple per row.
  defp tuples([], data, _bins), do: List.duplicate({}, data.count)

  defp tuples(channels, data, bins) do
    channels
    |> Enum.map(fn {name, channel} -> column(channel, data, bins[name]) end)
    |> Enum.zip()
  end

  defp step(funs, acc, values) do
    funs
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {{_name, fun}, i}, acc ->
      put_elem(acc, i, add(fun, elem(acc, i), elem(values, i)))
    end)
  end

  defp finish(funs, acc) do
    funs
    |> Enum.with_index()
    |> Map.new(fn {{name, fun}, i} -> {name, done(fun, elem(acc, i))} end)
  end

  # The running aggregates: a start, a step for each value, and the end.
  defp start(:count), do: 0
  defp start(:mean), do: {0, 0}
  defp start(fun) when fun in [:median, :distinct], do: []
  defp start(_fun), do: nil

  defp add(_fun, acc, nil), do: acc
  defp add(:first, nil, value), do: value
  defp add(:first, acc, _value), do: acc
  defp add(:count, acc, _value), do: acc + 1
  defp add(fun, acc, value) when fun in [:median, :distinct], do: [value | acc]
  defp add(_fun, acc, value) when not is_number(value), do: acc
  defp add(:sum, acc, value), do: (acc || 0) + value
  defp add(:min, acc, value), do: if(acc == nil or value < acc, do: value, else: acc)
  defp add(:max, acc, value), do: if(acc == nil or value > acc, do: value, else: acc)
  defp add(:mean, {sum, n}, value), do: {sum + value, n + 1}

  defp done(:mean, {_sum, 0}), do: nil
  defp done(:mean, {sum, n}), do: sum / n
  defp done(fun, values) when fun in [:median, :distinct], do: aggregate(fun, values)
  defp done(_fun, acc), do: acc

  defp value_channels(kind) when kind in [:pie, :donut], do: [:value]
  defp value_channels(:heatmap), do: [:color]
  defp value_channels(:choropleth), do: [:color]
  defp value_channels(:bubble_map), do: [:size, :color]
  defp value_channels(_kind), do: [:y]

  defp column(%Channel{aggregate: :count, field: nil}, data, _bins),
    do: List.duplicate(1, data.count)

  defp column(%Channel{value: value, field: nil}, data, _bins),
    do: List.duplicate(value, data.count)

  defp column(%Channel{field: field, time: nil}, data, nil), do: Map.fetch!(data.columns, field)

  defp column(%Channel{field: field, time: unit}, data, nil) do
    data.columns
    |> Map.fetch!(field)
    |> Enum.map(&if(is_integer(&1), do: Rules.floor(&1, unit), else: &1))
  end

  defp column(%Channel{field: field}, data, bins) do
    data.columns
    |> Map.fetch!(field)
    |> Enum.map(&if(is_number(&1), do: Rules.bin(bins, &1)))
  end

  defp bin_spec(%Channel{field: field, bin: bin}, data) do
    case data |> Data.column(field) |> Enum.filter(&is_number/1) do
      [] ->
        {0.0, 1.0, 1}

      numbers ->
        {min, max} = Enum.min_max(numbers)
        bins_of(min, max, bin)
    end
  end

  # The bins from the least to the greatest value: of a step, or about a
  # count of them.
  defp bins_of(min, max, %{step: step}) do
    start = Float.floor(min / step) * step
    {start, step / 1, max(1, ceil((max - start) / step))}
  end

  defp bins_of(min, max, %{count: count}), do: Rules.bins(min, max, count)
  defp bins_of(min, max, _bin), do: Rules.bins(min, max, 20)

  @doc false
  def aggregate(:count, values), do: Enum.count(values, &(not is_nil(&1)))

  def aggregate(:distinct, values),
    do: values |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length()

  def aggregate(fun, values) do
    case Enum.filter(values, &is_number/1) do
      [] -> nil
      numbers -> numeric(fun, numbers)
    end
  end

  defp numeric(:sum, numbers), do: Enum.sum(numbers)
  defp numeric(:mean, numbers), do: Enum.sum(numbers) / length(numbers)
  defp numeric(:min, numbers), do: Enum.min(numbers)
  defp numeric(:max, numbers), do: Enum.max(numbers)

  defp numeric(:median, numbers) do
    sorted = Enum.sort(numbers)
    count = length(sorted)
    middle = div(count, 2)

    if rem(count, 2) == 1,
      do: Enum.at(sorted, middle),
      else: (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2
  end

  # -- Marks of the kinds ------------------------------------------------------

  # A waterfall: each step a bar from the total before it to the total
  # after it, colored by whether it goes up or down; a first bar named as
  # the start, and a last bar of the end, are totals that stand on zero.
  defp marks(:waterfall, layer, %{rows: rows}, data) do
    start = layer.options[:start]

    {rows, total} =
      Enum.map_reduce(rows, 0, fn row, total ->
        value = row[:y] || 0

        if start && row[:x] == start,
          do: {Map.merge(row, %{y0: 0, y1: value, color: "Total"}), value},
          else:
            {Map.merge(row, %{y0: total, y1: total + value, color: change(value)}), total + value}
      end)

    rows =
      case layer.options[:total] do
        nil -> rows
        name -> rows ++ [%{x: name, y: total, y0: 0, y1: total, color: "Total"}]
      end

    values = Enum.flat_map(rows, &[&1.y0, &1.y1])
    x = band(layer.channels.x, data, rows, :x, layer.channels)

    y =
      number(layer.channels.y, data, if(values == [], do: nil, else: Enum.min_max(values)),
        zero: true,
        stack: false
      )

    colors =
      Enum.filter(["Increase", "Decrease", "Total"], fn name ->
        Enum.any?(rows, &(&1.color == name))
      end)

    %{
      mark: "bar",
      layer: layer,
      rows: rows,
      channels: %{x: :x, y: :y},
      stack: :waterfall,
      scales: %{
        "x" => x,
        "y" => y,
        "color" => %{"type" => "ordinal", "domain" => colors, "roles" => roles(colors)}
      },
      options: Map.merge(%{connectors: true}, Map.take(layer.options, [:labels]))
    }
  end

  # A funnel: centered bars, each with its share of the first stage.
  defp marks(:funnel, layer, %{rows: rows}, data) do
    first = rows |> List.first(%{}) |> Map.get(:y)

    rows =
      Enum.map(rows, fn row ->
        value = row[:y] || 0
        share = if is_number(first) and first != 0, do: value / first
        Map.merge(row, %{y0: -value / 2, y1: value / 2, share: share})
      end)

    max = rows |> Enum.map(&abs(&1[:y] || 0)) |> Enum.max(fn -> 1 end)

    %{
      mark: "bar",
      layer: layer,
      rows: rows,
      channels: %{x: :x, y: :y},
      horizontal: true,
      stack: :center,
      scales:
        %{
          "y" => band(layer.channels.x, data, rows, :x, layer.channels),
          "x" => %{
            "type" => "linear",
            "domain" => [-max / 2, max / 2],
            "nice" => false,
            "title" => Channel.title(layer.channels.y),
            "format" => format(layer.channels.y)
          }
        }
        |> put_color(layer.channels[:color], data, rows)
        |> stage_legend(layer.channels),
      options:
        layer.options
        |> Map.take([:step, :labels])
        |> Map.put(:funnel, true)
    }
  end

  defp marks(kind, layer, %{rows: rows, bins: bins}, data) when kind in [:bar, :histogram] do
    horizontal = layer.options[:horizontal] == true
    {x, y} = {layer.channels.x, layer.channels.y}
    color = layer.channels[:color]

    # Bars over time are in time order, as their axis is.
    rows = if x_type(x, data) == :time, do: Enum.sort_by(rows, &sort_key(&1[:x])), else: rows

    stack = stack_mode(y, color, kind)
    {rows, y_extent} = stack(rows, :x, stack, series(rows, color))

    {rows, x_scale} =
      case bins[:x] do
        nil ->
          {rows, band(x, data, rows, :x, layer.channels)}

        {start, step, _n} ->
          scale = bin_scale(x, start, step, rows)
          rows = rows |> Enum.reject(&is_nil(&1[:x])) |> Enum.sort_by(& &1[:x])

          {Enum.map(
             rows,
             &Map.merge(&1, %{x: start + &1[:x] * step, x2: start + (&1[:x] + 1) * step})
           ), scale}
      end

    y_scale = number(y, data, y_extent, zero: true, stack: stack)
    scales = %{position(:x, horizontal) => x_scale, position(:y, horizontal) => y_scale}
    scales = put_color(scales, color, data, rows)

    %{
      mark: "bar",
      layer: layer,
      rows: rows,
      channels: %{x: :x, y: :y},
      horizontal: horizontal,
      stack: stack,
      scales: scales,
      options: Map.take(layer.options, [:labels])
    }
  end

  defp marks(kind, layer, %{rows: rows}, data) when kind in [:line, :area, :sparkline] do
    {x, y} = {layer.channels.x, layer.channels.y}
    color = layer.channels[:color]
    stack = if kind == :area, do: stack_mode(y, color, :area), else: false

    rows = Enum.sort_by(rows, &sort_key(&1[:x]))
    {rows, y_extent} = stack(rows, :x, stack, series(rows, color))

    x_scale =
      case x_type(x, data) do
        :category -> band(x, data, rows, :x, layer.channels) |> Map.put("type", "point")
        type -> continuous(x, data, rows, :x, type)
      end

    zero = kind == :area or (y.scale && y.scale[:zero]) == true
    scales = %{"x" => x_scale, "y" => number(y, data, y_extent, zero: zero, stack: stack)}

    %{
      mark: if(kind == :area, do: "area", else: "line"),
      layer: layer,
      rows: rows,
      channels: %{x: :x, y: :y},
      stack: stack,
      scales: put_color(scales, color, data, rows),
      options: Map.take(layer.options, [:curve, :points, :labels, :area, :value])
    }
  end

  defp marks(kind, layer, %{rows: rows}, data) when kind in [:scatter, :bubble] do
    {x, y} = {layer.channels.x, layer.channels.y}
    color = layer.channels[:color]
    size = layer.channels[:size]

    scales = %{
      "x" => continuous_or_band(x, data, rows, :x, layer.channels),
      "y" => continuous_or_band(y, data, rows, :y, layer.channels)
    }

    scales = put_color(scales, color, data, rows)

    scales =
      if size do
        Map.put(scales, "size", %{
          "type" => "sqrt",
          "domain" => extent(rows, :size) |> with_zero(),
          "title" => Channel.title(size)
        })
      else
        scales
      end

    %{
      mark: "point",
      layer: layer,
      rows: rows,
      channels: %{x: :x, y: :y},
      scales: scales,
      options: %{}
    }
  end

  defp marks(kind, layer, %{rows: rows}, data) when kind in [:pie, :donut] do
    color = layer.channels.color
    rows = Enum.filter(rows, &(is_number(&1[:value]) and &1[:value] > 0))
    total = rows |> Enum.map(& &1[:value]) |> Enum.sum()

    {rows, _} =
      Enum.map_reduce(rows, 0, fn row, at ->
        share = if total > 0, do: row[:value] / total, else: 0
        {Map.merge(row, %{a0: at, a1: at + share}), at + share}
      end)

    scales = put_color(%{}, color, data, rows)

    %{
      mark: "arc",
      layer: layer,
      rows: rows,
      channels: %{},
      scales: scales,
      options: %{
        inner: if(kind == :donut, do: layer.options[:inner] || 0.6, else: 0),
        labels: layer.options[:labels] != false
      }
    }
  end

  defp marks(:heatmap, layer, %{rows: rows}, data) do
    {x, y} = {layer.channels.x, layer.channels.y}
    color = layer.channels[:color]

    scales = %{
      "x" => band(x, data, rows, :x, layer.channels),
      "y" => band(y, data, rows, :y, layer.channels)
    }

    scales =
      case color do
        %Channel{} = channel ->
          if x_type(channel, data) == :number or channel.aggregate do
            Map.put(
              scales,
              "color",
              scheme(
                %{
                  "type" => "sequential",
                  "domain" => extent(rows, :color) |> pair(),
                  "title" => Channel.title(channel)
                },
                channel
              )
            )
          else
            put_color(scales, color, data, rows)
          end

        nil ->
          scales
      end

    %{
      mark: "rect",
      layer: layer,
      rows: rows,
      channels: %{x: :x, y: :y},
      scales: scales,
      options: Map.take(layer.options, [:labels])
    }
  end

  defp marks(kind, layer, %{rows: rows}, data) when kind in [:choropleth, :bubble_map] do
    region = layer.channels.region
    values = rows |> Enum.map(& &1[:region]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    scales = %{
      "region" => %{"type" => "ordinal", "domain" => values, "title" => Channel.title(region)}
    }

    scales = put_color(scales, layer.channels[:color], data, rows)

    scales =
      case layer.channels[:size] do
        nil ->
          scales

        size ->
          Map.put(scales, "size", %{
            "type" => "sqrt",
            "domain" => extent(rows, :size) |> with_zero(),
            "title" => Channel.title(size),
            "format" => format(size)
          })
      end

    %{
      mark: if(kind == :choropleth, do: "region", else: "bubble"),
      layer: layer,
      rows: rows,
      channels: %{},
      scales: scales,
      options: %{map: layer.options[:map] || "world"}
    }
  end

  defp marks(:rule, layer, %{rows: rows}, data) do
    rows = Enum.uniq(rows)

    scales =
      for {name, channel} <- Map.take(layer.channels, [:x, :y]), into: %{} do
        {Atom.to_string(name), continuous_or_band(channel, data, rows, name, layer.channels)}
      end

    %{
      mark: "rule",
      layer: layer,
      rows: rows,
      channels: %{x: :x, y: :y},
      scales: scales,
      options: Map.take(layer.options, [:label, :dashed])
    }
  end

  defp marks(:text, layer, %{rows: rows}, data) do
    scales =
      for {name, channel} <- Map.take(layer.channels, [:x, :y]), into: %{} do
        {Atom.to_string(name), continuous_or_band(channel, data, rows, name, layer.channels)}
      end

    %{
      mark: "text",
      layer: layer,
      rows: rows,
      channels: %{x: :x, y: :y},
      scales: scales,
      options: %{}
    }
  end

  defp position(axis, false), do: Atom.to_string(axis)
  defp position(:x, true), do: "y"
  defp position(:y, true), do: "x"

  defp sort_key(nil), do: {1, 0}
  defp sort_key(value), do: {0, value}

  defp change(value) when value < 0, do: "Decrease"
  defp change(_value), do: "Increase"

  # The colors of a waterfall's bars, by their role rather than their order.
  defp roles(names), do: Enum.map(names, &(&1 |> String.downcase()))

  # -- Stacks ------------------------------------------------------------------

  defp stack_mode(%Channel{stack: false}, _color, _kind), do: false
  defp stack_mode(%Channel{stack: stack}, _color, _kind) when not is_nil(stack), do: stack
  defp stack_mode(_y, nil, _kind), do: false
  defp stack_mode(_y, _color, :histogram), do: :zero
  defp stack_mode(_y, _color, kind) when kind in [:bar, :area], do: :zero

  # Stacks the rows of each x (in the order of their colors): each gets its
  # base (y0) and its top (y1). Positive values stack up, negative down.
  defp stack(rows, _by, false, _series), do: {rows, extent(rows, :y)}

  # Each stack in the order of the series, as the legend has them, whatever
  # the order of the rows: the first series at the bottom of every stack.
  # The rows keep their order otherwise.
  defp stack(rows, by, mode, series) do
    place = series |> Enum.with_index() |> Map.new()

    {stacked, _} =
      rows
      |> Enum.with_index()
      |> Enum.sort_by(fn {row, i} -> {Map.get(place, row[:color], 0), i} end)
      |> Enum.map_reduce(%{}, fn {row, i}, acc ->
        {stacked, acc} = stack_row(row, acc, by)
        {{stacked, i}, acc}
      end)

    stacked = stacked |> Enum.sort_by(&elem(&1, 1)) |> Enum.map(&elem(&1, 0))
    stacked = offset(stacked, by, mode)
    values = Enum.flat_map(stacked, &[&1.y0, &1.y1])
    {stacked, if(values == [], do: nil, else: Enum.min_max(values))}
  end

  # The series of a layer in the order of its color scale: first seen, or
  # its channel's sort.
  defp series(_rows, nil), do: []

  defp series(rows, %Channel{} = color) do
    rows
    |> Enum.map(& &1[:color])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> order(color.sort, rows, :color, nil)
  end

  defp stack_row(row, acc, by) do
    value = row[:y] || 0
    {pos, neg} = Map.get(acc, row[by], {0, 0})

    if value >= 0,
      do:
        {Map.merge(row, %{y0: pos, y1: pos + value}), Map.put(acc, row[by], {pos + value, neg})},
      else:
        {Map.merge(row, %{y0: neg, y1: neg + value}), Map.put(acc, row[by], {pos, neg + value})}
  end

  # A stack to 100%, or around its middle.
  defp offset(stacked, by, :normalize) do
    totals = totals(stacked, by, &abs(&1[:y] || 0))
    Enum.map(stacked, &share(&1, totals[&1[by]]))
  end

  defp offset(stacked, by, :center) do
    totals = totals(stacked, by, &(&1[:y] || 0))
    Enum.map(stacked, &%{&1 | y0: &1.y0 - totals[&1[by]] / 2, y1: &1.y1 - totals[&1[by]] / 2})
  end

  defp offset(stacked, _by, _mode), do: stacked

  defp share(row, total) when total > 0, do: %{row | y0: row.y0 / total, y1: row.y1 / total}
  defp share(row, _total), do: row

  defp totals(rows, by, value) do
    rows |> Enum.group_by(& &1[by], value) |> Map.new(fn {k, v} -> {k, Enum.sum(v)} end)
  end

  # -- Scales ------------------------------------------------------------------

  defp x_type(%Channel{type: type}, _data) when type in [:number, :time], do: type
  defp x_type(%Channel{type: type}, _data) when type in [:category, :ordinal], do: :category

  defp x_type(%Channel{aggregate: aggregate}, _data) when aggregate in [:count, :distinct],
    do: :number

  defp x_type(%Channel{field: nil, value: value}, _data) when is_number(value), do: :number
  defp x_type(%Channel{field: nil}, _data), do: :category

  defp x_type(%Channel{field: field}, data) do
    case Data.field(data, field) do
      %{type: type} -> type
      nil -> :category
    end
  end

  defp continuous_or_band(channel, data, rows, name, channels) do
    case x_type(channel, data) do
      :category -> band(channel, data, rows, name, channels)
      :number -> number(channel, data, extent(rows, name), zero: false, stack: false)
      :time -> continuous(channel, data, rows, name, :time)
    end
  end

  defp continuous(channel, data, rows, name, :time) do
    field = channel.field && Data.field(data, channel.field)

    %{
      "type" => "time",
      "domain" => extent(rows, name) |> pair(),
      "unit" => unit(channel, field),
      "title" => Channel.title(channel),
      "format" => format(channel)
    }
  end

  defp continuous(channel, data, rows, name, :number),
    do: number(channel, data, extent(rows, name), zero: false, stack: false)

  defp unit(%Channel{time: unit}, _field) when not is_nil(unit), do: Atom.to_string(unit)
  defp unit(_channel, %{unit: unit}) when not is_nil(unit), do: Atom.to_string(unit)
  defp unit(_channel, _field), do: nil

  defp number(channel, _data, extent, opts) do
    scale = channel.scale || %{}
    zero = Map.get(scale, :zero, opts[:zero])

    domain =
      case scale[:domain] do
        [min, max] when is_number(min) and is_number(max) -> [min, max]
        _ -> extent |> pair() |> then(&if(zero && &1, do: with_zero(&1), else: &1))
      end

    %{
      "type" => Atom.to_string(scale[:type] || :linear),
      "domain" => domain,
      "nice" => Map.get(scale, :nice, scale[:domain] == nil),
      "title" => Channel.title(channel),
      "format" => if(opts[:stack] == :normalize, do: "percent", else: format(channel))
    }
  end

  defp bin_scale(channel, start, step, rows) do
    n = rows |> Enum.map(& &1[:x]) |> Enum.reject(&is_nil/1) |> Enum.max(fn -> 0 end)

    %{
      "type" => "linear",
      "domain" => [start, start + (n + 1) * step],
      "nice" => false,
      "bins" => %{"start" => start, "step" => step},
      "title" => Channel.title(channel),
      "format" => format(channel)
    }
  end

  # A band scale: its categories in order: as given, sorted, or in the
  # order of their first row. A time with a unit is a category of a band
  # (a bar for each month), in time order.
  defp band(channel, data, rows, name, channels) do
    values = rows |> Enum.map(& &1[name]) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    time = channel.field && Data.field(data, channel.field) |> then(&(&1 && &1.type == :time))

    values =
      if time == true and not is_list(channel.sort),
        do: Enum.sort(values),
        else: order(values, channel.sort, rows, name, channels)

    %{
      "type" => "band",
      "domain" => values,
      "time" => if(time, do: unit(channel, Data.field(data, channel.field)) || "day"),
      "title" => Channel.title(channel),
      "format" => format(channel)
    }
  end

  # Categories in an order: as given, sorted, by another channel, or in the
  # order of their first row.
  defp order(values, sort, _rows, _name, _channels) when is_list(sort),
    do: sort ++ (values -- sort)

  defp order(values, :ascending, _rows, _name, _channels), do: Enum.sort(values)
  defp order(values, :descending, _rows, _name, _channels), do: Enum.sort(values, :desc)

  defp order(values, sort, rows, name, channels) when sort in [:x, :y, :"-x", :"-y"],
    do: sort_by_channel(values, rows, name, sort, channels)

  defp order(values, _sort, _rows, _name, _channels), do: values

  defp sort_by_channel(values, rows, name, sort, _channels) do
    {by, order} =
      case sort do
        :x -> {:x, :asc}
        :y -> {:y, :asc}
        :"-x" -> {:x, :desc}
        :"-y" -> {:y, :desc}
      end

    totals =
      rows
      |> Enum.group_by(& &1[name], &(&1[by] || 0))
      |> Map.new(fn {key, list} ->
        {key, if(Enum.all?(list, &is_number/1), do: Enum.sum(list), else: 0)}
      end)

    Enum.sort_by(values, &Map.get(totals, &1, 0), order)
  end

  # A funnel colored by its stages has no legend: its axis names them.
  defp stage_legend(%{"color" => color} = scales, %{
         x: %Channel{field: field},
         color: %Channel{field: field}
       }),
       do: %{scales | "color" => Map.put(color, "legend", false)}

  defp stage_legend(scales, _channels), do: scales

  defp put_color(scales, nil, _data, _rows), do: scales

  defp put_color(scales, %Channel{} = channel, data, rows) do
    if x_type(channel, data) == :number and channel.field do
      Map.put(
        scales,
        "color",
        scheme(
          %{
            "type" => "sequential",
            "domain" => extent(rows, :color) |> pair(),
            "title" => Channel.title(channel),
            "format" => format(channel)
          },
          channel
        )
      )
    else
      values = rows |> Enum.map(& &1[:color]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

      values = order(values, channel.sort, rows, :color, nil)

      Map.put(
        scales,
        "color",
        scheme(
          %{"type" => "ordinal", "domain" => values, "title" => Channel.title(channel)},
          channel
        )
      )
    end
  end

  # A color scale's scheme: its name or its list of colors, and the middle
  # of a diverging one (0 unless given).
  defp scheme(scale, %Channel{scheme: nil}), do: scale

  defp scheme(scale, %Channel{scheme: scheme, mid: mid}) do
    mid = if is_atom(scheme) and Channel.diverging?(scheme), do: mid || 0, else: mid

    scale
    |> Map.put("scheme", if(is_atom(scheme), do: Atom.to_string(scheme), else: scheme))
    |> Map.put("mid", mid)
  end

  defp extent(rows, name) do
    case rows |> Enum.map(& &1[name]) |> Enum.filter(&is_number/1) do
      [] -> nil
      values -> Enum.min_max(values)
    end
  end

  defp pair(nil), do: nil
  defp pair({min, max}), do: [min, max]
  defp pair([_, _] = pair), do: pair

  defp with_zero(nil), do: [0, 1]
  defp with_zero({min, max}), do: [min(min, 0), max(max, 0)]
  defp with_zero([min, max]), do: [min(min, 0), max(max, 0)]

  # Scales of the same channel in several layers: one domain for all.
  defp merge_scales(acc, scales) do
    Map.merge(acc, scales, fn _name, a, b -> merge_scale(a, b) end)
  end

  # Categories: all of both, in order. A waterfall's roles follow its names.
  defp merge_scale(%{"type" => type} = a, %{"type" => type} = b)
       when type in ["band", "point", "ordinal"] do
    domain = Enum.uniq(a["domain"] ++ b["domain"])
    merged = %{a | "domain" => domain}
    if a["roles"], do: %{merged | "roles" => roles(domain)}, else: merged
  end

  defp merge_scale(%{"domain" => [a0, a1]} = a, %{"domain" => [b0, b1]})
       when is_number(a0) and is_number(b0),
       do: %{a | "domain" => [min(a0, b0), max(a1, b1)]}

  defp merge_scale(%{"domain" => nil}, b), do: b
  defp merge_scale(a, _b), do: a

  defp finish_scales(scales) do
    Map.new(scales, fn {name, scale} ->
      {name, scale |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()}
    end)
  end

  # A channel's format as the browser reads it: "number", "currency:EUR",
  # with its digits after a colon when it has them ("number:0",
  # "currency:EUR:2", ":0" with no format).
  defp format(nil), do: nil
  defp format(%Channel{digits: nil} = channel), do: base_format(channel)
  defp format(%Channel{digits: digits} = channel), do: "#{base_format(channel)}:#{digits}"

  defp base_format(%Channel{format: {:currency, code}}), do: "currency:" <> code

  defp base_format(%Channel{format: format}) when is_atom(format) and not is_nil(format),
    do: Atom.to_string(format)

  defp base_format(_channel), do: nil

  # -- Encoding ----------------------------------------------------------------

  # A layer's columns, each value as the browser draws it: a category as
  # its index in its scale's domain.
  defp encode(table, scales) do
    %{rows: rows, mark: mark} = table
    swap = Map.get(table, :horizontal, false)
    right? = Map.get(table, :axis) == :right

    # Every row of a layer has the same keys.
    present = rows |> List.first(%{}) |> Map.keys()

    columns =
      [:x, :x2, :y, :y0, :y1, :color, :size, :value, :a0, :a1, :text, :region, :share]
      |> Enum.filter(&(&1 in present))
      |> Map.new(fn name ->
        target = column_name(name, swap)
        scale = if right? and scale_name(target) == "y", do: "yRight", else: scale_name(target)
        encode = encoder(scales[scale])
        {Atom.to_string(target), Enum.map(rows, &encode.(&1[name]))}
      end)

    tooltip = tooltip(table, rows)

    %{
      "mark" => mark,
      "n" => length(rows),
      "columns" => columns,
      "axis" => if(Map.get(table, :axis) == :right, do: "right", else: nil),
      "horizontal" => swap,
      "stack" => stack_name(Map.get(table, :stack, false)),
      "options" => Map.new(table.options, fn {k, v} -> {Atom.to_string(k), dump(v)} end),
      "tooltip" => tooltip
    }
  end

  defp stack_name(false), do: nil
  defp stack_name(mode), do: Atom.to_string(mode)

  defp column_name(name, false), do: name
  defp column_name(:x, true), do: :y
  defp column_name(:y, true), do: :x
  defp column_name(:y0, true), do: :x0
  defp column_name(:y1, true), do: :x1
  defp column_name(:x2, true), do: :y2
  defp column_name(name, true), do: name

  defp scale_name(name) when name in [:x, :x0, :x1, :x2], do: "x"
  defp scale_name(name) when name in [:y, :y0, :y1, :y2], do: "y"
  defp scale_name(name), do: Atom.to_string(name)

  # A category goes as its index in its scale's domain, found in a map of
  # the domain; any other value as it is.
  defp encoder(%{"type" => type, "domain" => domain}) when type in ["band", "point", "ordinal"] do
    index = domain |> Enum.with_index() |> Map.new()
    &(&1 && Map.get(index, &1))
  end

  defp encoder(_scale), do: & &1

  # The fields of the tooltip beyond the channels: their titles, formats
  # and values, by row; a time as milliseconds, with its unit.
  defp tooltip(%{layer: %Layer{} = layer}, rows) do
    Enum.map(tips(layer), fn {name, channel} ->
      values = Enum.map(rows, &tip_value(&1[name]))

      %{
        "title" => Channel.title(channel),
        "format" => format(channel),
        "time" => if(channel.type == :time, do: time_unit(channel, values)),
        "values" => values
      }
    end)
  end

  # A time's unit: its channel's, or a day when every value is a midnight
  # (a date), or "" for a time of a day.
  defp time_unit(%Channel{time: unit}, _values) when not is_nil(unit), do: Atom.to_string(unit)

  defp time_unit(_channel, values) do
    if Enum.all?(values, &(not is_integer(&1) or rem(&1, 86_400_000) == 0)),
      do: "day",
      else: ""
  end

  defp tip_value(value) when is_number(value) or is_binary(value) or is_boolean(value),
    do: value

  defp tip_value(nil), do: nil
  defp tip_value(value), do: to_string(value)

  defp dump(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  defp dump(value), do: value

  # -- The table ---------------------------------------------------------------

  @doc false
  # The data that the chart draws, as a table: the first layer's columns
  # by their titles, a category by its name, a time as a Date (a time of
  # a day or more) or a DateTime. The page's table and Fude.Test read it.
  @spec table(map()) :: {[String.t()], [[term()]]}
  def table(%{"facet" => %{"title" => title, "panels" => panels}, "scales" => scales}) do
    panels
    |> Enum.map(fn panel ->
      {panel["title"], table(%{"layers" => panel["layers"], "scales" => scales})}
    end)
    |> Enum.reduce({[], []}, fn {name, {heads, rows}}, {_, all} ->
      {[title | heads], all ++ Enum.map(rows, &[name | &1])}
    end)
    |> then(fn {heads, rows} -> {heads, Enum.take(rows, 1000)} end)
  end

  def table(%{"layers" => [layer | _], "scales" => scales}) do
    columns =
      [{"x", "x"}, {"y", "y"}, {"color", "color"}, {"size", "size"}, {"value", nil}]
      |> Enum.filter(fn {name, _scale} -> Map.has_key?(layer["columns"], name) end)

    heads =
      Enum.map(columns, fn
        {"value", _} -> "Value"
        {name, scale} -> get_in(scales, [scale, "title"]) || name
      end)

    values =
      Enum.map(columns, fn {name, scale_name} ->
        scale = scales[scale_name]
        Enum.map(layer["columns"][name], &cell(&1, scale))
      end)

    rows =
      case values do
        [] -> []
        values -> values |> Enum.zip() |> Enum.map(&Tuple.to_list/1)
      end

    {heads, Enum.take(rows, 1000)}
  end

  def table(_wire), do: {[], []}

  defp cell(nil, _scale), do: nil

  defp cell(index, %{"type" => type, "domain" => domain} = scale)
       when type in ["band", "point", "ordinal"],
       do: domain |> Enum.at(index) |> cell_value(scale)

  defp cell(value, scale), do: cell_value(value, scale)

  @days ~w(day week month quarter year)

  defp cell_value(value, %{"type" => "time", "unit" => unit})
       when is_integer(value) and unit in @days,
       do: day(value)

  defp cell_value(value, %{"time" => unit}) when is_integer(value) and unit in @days,
    do: day(value)

  defp cell_value(value, %{"type" => "time"}) when is_integer(value),
    do: DateTime.from_unix!(value, :millisecond)

  defp cell_value(value, %{"time" => _unit}) when is_integer(value),
    do: DateTime.from_unix!(value, :millisecond)

  defp cell_value(value, _scale), do: value

  defp day(ms), do: Date.add(~D[1970-01-01], Integer.floor_div(ms, 86_400_000))

  # -- Description -------------------------------------------------------------

  # What a screen reader says of a chart that has no description of its
  # own: the kind, what is on each axis, and the extremes.
  defp describe(chart, _layers, scales) do
    kind = Chart.kind(chart)

    words =
      [
        chart.title,
        "#{article(kind)} #{kind_name(kind)}",
        axis_words("x", scales["x"]),
        axis_words("y", scales["y"]),
        region_words(scales["region"]),
        color_words(scales["color"]),
        size_words(scales["size"])
      ]
      |> Enum.reject(&(&1 in [nil, ""]))

    Enum.join(words, ". ") <> "."
  end

  defp article(kind) when kind in [:area, :histogram], do: "An"
  defp article(_kind), do: "A"

  defp kind_name(:bar), do: "bar chart"
  defp kind_name(:line), do: "line chart"
  defp kind_name(:area), do: "area chart"
  defp kind_name(:scatter), do: "scatter plot"
  defp kind_name(:bubble), do: "bubble chart"
  defp kind_name(:pie), do: "pie chart"
  defp kind_name(:donut), do: "donut chart"
  defp kind_name(:histogram), do: "histogram"
  defp kind_name(:heatmap), do: "heatmap"
  defp kind_name(:sparkline), do: "sparkline"
  defp kind_name(:choropleth), do: "map"
  defp kind_name(:waterfall), do: "waterfall chart"
  defp kind_name(:funnel), do: "funnel"
  defp kind_name(:bubble_map), do: "map"
  defp kind_name(kind), do: "#{kind} chart"

  defp axis_words(_name, nil), do: nil

  defp axis_words(name, %{"type" => "band", "domain" => domain} = scale),
    do: "#{name} axis, #{scale["title"] || "categories"}: #{length(domain)} categories"

  defp axis_words(name, %{"domain" => [min, max]} = scale),
    do:
      "#{name} axis, #{scale["title"] || "values"}: from #{plain(min, scale)} to #{plain(max, scale)}"

  defp axis_words(_name, _scale), do: nil

  defp color_words(%{"type" => "ordinal", "domain" => domain} = scale) when domain != [],
    do: "#{length(domain)} series by #{scale["title"]}: #{Enum.join(Enum.take(domain, 8), ", ")}"

  defp color_words(%{"type" => "sequential", "domain" => [min, max]} = scale),
    do: "color, #{scale["title"]}: from #{plain(min, scale)} to #{plain(max, scale)}"

  defp color_words(_scale), do: nil

  defp region_words(%{"domain" => domain} = scale),
    do: "#{length(domain)} regions by #{scale["title"]}"

  defp region_words(_scale), do: nil

  defp size_words(%{"domain" => [_, max]} = scale) when is_number(max),
    do: "size, #{scale["title"]}: up to #{plain(max, scale)}"

  defp size_words(_scale), do: nil

  defp plain(value, %{"type" => "time", "unit" => "day"}) when is_integer(value),
    do: value |> div(86_400_000) |> then(&Date.add(~D[1970-01-01], &1)) |> Date.to_iso8601()

  defp plain(value, %{"type" => "time"}) when is_integer(value),
    do: value |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601()

  defp plain(value, _scale) when is_float(value), do: :erlang.float_to_binary(value, [:short])
  defp plain(value, _scale), do: to_string(value)
end
