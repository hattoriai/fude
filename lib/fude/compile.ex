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
    data = datasets |> Map.get(chart.data) |> Data.new()

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

  @doc false
  # Every field that a channel reads is in the data.
  def check_fields(%Chart{layers: layers}, data) do
    names = Data.names(data)

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

    if errors == [], do: :ok, else: {:error, Enum.uniq(errors)}
  end

  defp build(chart, data) do
    single? = Chart.kind(chart) in [:number, :trend, :progress]

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
    end
  end

  defp arcs?(chart), do: Enum.all?(chart.layers, &(&1.kind in [:pie, :donut]))

  # -- Single values ---------------------------------------------------------

  defp single(%Layer{kind: kind, channels: channels, options: options}, data) do
    value = first_value(channels[:value], data)

    %{
      "value" => value,
      "label" => options[:label] || Channel.title(channels[:value]),
      "format" => format(channels[:value]),
      "compare" => if(kind == :trend, do: compare(channels[:compare], channels[:value], data)),
      "goal" => if(kind == :progress, do: options[:goal] || 100)
    }
  end

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
  # the columns of each layer as the scales encode them.
  defp layers(layers, data) do
    tables = Enum.map(layers, &table(&1, data))
    scales = Enum.reduce(tables, %{}, &merge_scales(&2, &1.scales))
    {Enum.map(tables, &encode(&1, scales)), scales}
  end

  # The marks of each kind, and how its channels go to the mark's.
  defp table(%Layer{kind: kind} = layer, data) do
    layer = normalize(layer)
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

  # The rows of a layer: the data with each channel's value, its time
  # unit taken and its bin found, then grouped by the channels that are
  # not aggregated, with the others aggregated. A bar or an area sums the
  # values of a group when its channel has no aggregate, so that a bar is
  # one bar.
  defp rows(%Layer{kind: kind, channels: channels}, data) do
    channels = Map.delete(channels, :tooltip) |> Map.to_list()

    bins =
      Map.new(for {name, %Channel{bin: bin} = c} <- channels, bin, do: {name, bin_spec(c, data)})

    values =
      Enum.map(0..(data.count - 1)//1, fn index ->
        Map.new(channels, fn {name, channel} ->
          {name, row_value(channel, data, index, bins[name])}
        end)
      end)

    # A layer of constants only (a rule at y: 1000) is one row.
    values =
      if Enum.all?(channels, fn {_name, channel} ->
           is_nil(channel.field) and channel.aggregate != :count
         end),
         do: [Map.new(channels, fn {name, channel} -> {name, channel.value} end)],
         else: values

    implicit = if kind in [:bar, :area, :heatmap, :pie, :donut], do: :sum

    aggregated =
      for {name, %Channel{} = channel} <- channels,
          channel.aggregate ||
            (implicit && name in value_channels(kind) && channel.field && !channel.bin),
          into: %{},
          do: {name, channel.aggregate || implicit}

    rows =
      if aggregated == %{} do
        values
      else
        keys = for {name, _channel} <- channels, not Map.has_key?(aggregated, name), do: name

        values
        |> Enum.group_by(&Map.take(&1, keys))
        |> Enum.map(fn {key, group} ->
          Map.merge(
            key,
            Map.new(aggregated, fn {name, fun} ->
              {name, aggregate(fun, Enum.map(group, & &1[name]))}
            end)
          )
        end)
        |> order_groups(values, keys)
      end

    %{rows: rows, bins: bins}
  end

  defp value_channels(kind) when kind in [:pie, :donut], do: [:value]
  defp value_channels(:heatmap), do: [:color]
  defp value_channels(_kind), do: [:y]

  # Groups keep the order of their first row: the order of the query.
  defp order_groups(groups, values, keys) do
    order =
      values
      |> Enum.map(&Map.take(&1, keys))
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {key, index}, acc -> Map.put_new(acc, key, index) end)

    Enum.sort_by(groups, &Map.get(order, Map.take(&1, keys)))
  end

  defp row_value(%Channel{aggregate: :count, field: nil}, _data, _index, _bin), do: 1
  defp row_value(%Channel{value: value, field: nil}, _data, _index, _bin), do: value

  defp row_value(%Channel{field: field, time: unit}, data, index, nil) do
    value = data.columns |> Map.fetch!(field) |> Enum.at(index)

    if unit && is_integer(value), do: Rules.floor(value, unit), else: value
  end

  defp row_value(%Channel{field: field}, data, index, bins) do
    case data.columns |> Map.fetch!(field) |> Enum.at(index) do
      value when is_number(value) -> Rules.bin(bins, value)
      _ -> nil
    end
  end

  defp bin_spec(%Channel{field: field, bin: bin}, data) do
    numbers = data |> Data.column(field) |> Enum.filter(&is_number/1)

    case numbers do
      [] ->
        {0.0, 1.0, 1}

      numbers ->
        {min, max} = Enum.min_max(numbers)

        case bin do
          %{step: step} ->
            start = Float.floor(min / step) * step
            {start, step / 1, max(1, ceil((max - start) / step))}

          %{count: count} ->
            Rules.bins(min, max, count)

          true ->
            Rules.bins(min, max, 20)
        end
    end
  end

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

  defp marks(kind, layer, %{rows: rows, bins: bins}, data) when kind in [:bar, :histogram] do
    horizontal = layer.options[:horizontal] == true
    {x, y} = {layer.channels.x, layer.channels.y}
    color = layer.channels[:color]

    stack = stack_mode(y, color, kind)
    {rows, y_extent} = stack(rows, :x, stack)

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
    {rows, y_extent} = stack(rows, :x, stack)

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
      options: Map.take(layer.options, [:curve, :points, :labels])
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
            Map.put(scales, "color", %{
              "type" => "sequential",
              "domain" => extent(rows, :color) |> pair(),
              "title" => Channel.title(channel)
            })
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

  # -- Stacks ------------------------------------------------------------------

  defp stack_mode(%Channel{stack: false}, _color, _kind), do: false
  defp stack_mode(%Channel{stack: stack}, _color, _kind) when not is_nil(stack), do: stack
  defp stack_mode(_y, nil, _kind), do: false
  defp stack_mode(_y, _color, :histogram), do: :zero
  defp stack_mode(_y, _color, kind) when kind in [:bar, :area], do: :zero

  # Stacks the rows of each x (in the order of their colors): each gets its
  # base (y0) and its top (y1). Positive values stack up, negative down.
  defp stack(rows, _by, false), do: {rows, extent(rows, :y)}

  defp stack(rows, by, mode) do
    {stacked, _} =
      Enum.map_reduce(rows, %{}, fn row, acc ->
        value = row[:y] || 0
        {pos, neg} = Map.get(acc, row[by], {0, 0})

        if value >= 0 do
          {Map.merge(row, %{y0: pos, y1: pos + value}), Map.put(acc, row[by], {pos + value, neg})}
        else
          {Map.merge(row, %{y0: neg, y1: neg + value}), Map.put(acc, row[by], {pos, neg + value})}
        end
      end)

    stacked =
      case mode do
        :normalize ->
          totals =
            Enum.group_by(stacked, & &1[by], &abs(&1[:y] || 0))
            |> Map.new(fn {k, v} -> {k, Enum.sum(v)} end)

          Enum.map(stacked, fn row ->
            total = totals[row[by]]
            if total > 0, do: %{row | y0: row.y0 / total, y1: row.y1 / total}, else: row
          end)

        :center ->
          totals =
            Enum.group_by(stacked, & &1[by], &(&1[:y] || 0))
            |> Map.new(fn {k, v} -> {k, Enum.sum(v)} end)

          Enum.map(stacked, fn row ->
            %{row | y0: row.y0 - totals[row[by]] / 2, y1: row.y1 - totals[row[by]] / 2}
          end)

        _ ->
          stacked
      end

    values = Enum.flat_map(stacked, &[&1.y0, &1.y1])
    {stacked, if(values == [], do: nil, else: Enum.min_max(values))}
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
      cond do
        is_list(channel.sort) ->
          channel.sort ++ (values -- channel.sort)

        time ->
          Enum.sort(values)

        channel.sort == :ascending ->
          Enum.sort(values)

        channel.sort == :descending ->
          Enum.sort(values, :desc)

        channel.sort in [:x, :y, :"-x", :"-y"] ->
          sort_by_channel(values, rows, name, channel.sort, channels)

        true ->
          values
      end

    %{
      "type" => "band",
      "domain" => values,
      "time" => if(time, do: unit(channel, Data.field(data, channel.field)) || "day"),
      "title" => Channel.title(channel),
      "format" => format(channel)
    }
  end

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

  defp put_color(scales, nil, _data, _rows), do: scales

  defp put_color(scales, %Channel{} = channel, data, rows) do
    if x_type(channel, data) == :number and channel.field do
      Map.put(scales, "color", %{
        "type" => "sequential",
        "domain" => extent(rows, :color) |> pair(),
        "title" => Channel.title(channel),
        "format" => format(channel)
      })
    else
      values = rows |> Enum.map(& &1[:color]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

      values =
        cond do
          is_list(channel.sort) -> channel.sort ++ (values -- channel.sort)
          channel.sort == :ascending -> Enum.sort(values)
          channel.sort == :descending -> Enum.sort(values, :desc)
          true -> values
        end

      Map.put(scales, "color", %{
        "type" => "ordinal",
        "domain" => values,
        "title" => Channel.title(channel)
      })
    end
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

  defp merge_scale(%{"type" => "band"} = a, %{"type" => "band"} = b),
    do: %{a | "domain" => Enum.uniq(a["domain"] ++ b["domain"])}

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

  defp format(nil), do: nil
  defp format(%Channel{format: {:currency, code}}), do: "currency:" <> code

  defp format(%Channel{format: format}) when is_atom(format) and not is_nil(format),
    do: Atom.to_string(format)

  defp format(_channel), do: nil

  # -- Encoding ----------------------------------------------------------------

  # A layer's columns, each value as the browser draws it: a category as
  # its index in its scale's domain.
  defp encode(table, scales) do
    %{rows: rows, mark: mark} = table
    swap = Map.get(table, :horizontal, false)

    columns =
      [:x, :x2, :y, :y0, :y1, :color, :size, :value, :a0, :a1, :text]
      |> Enum.filter(fn name -> Enum.any?(rows, &Map.has_key?(&1, name)) end)
      |> Map.new(fn name ->
        target = column_name(name, swap)
        scale = scales[scale_name(target)]
        {Atom.to_string(target), Enum.map(rows, &encode_value(&1[name], scale))}
      end)

    tooltip = tooltip(table, rows)

    %{
      "mark" => mark,
      "n" => length(rows),
      "columns" => columns,
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

  defp encode_value(nil, _scale), do: nil

  defp encode_value(value, %{"type" => type, "domain" => domain})
       when type in ["band", "point", "ordinal"],
       do: Enum.find_index(domain, &(&1 == value))

  defp encode_value(value, _scale), do: value

  # The fields of the tooltip beyond the channels: their titles, formats
  # and values, by row.
  defp tooltip(%{layer: %Layer{channels: channels}}, _rows) do
    case channels[:tooltip] do
      nil -> []
      list -> Enum.map(list, &%{"title" => Channel.title(&1), "format" => format(&1)})
    end
  end

  defp dump(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  defp dump(value), do: value

  # -- The table ---------------------------------------------------------------

  @doc false
  # The data that the chart draws, as a table: the first layer's columns
  # by their titles, a category by its name, a time as a Date (a time of
  # a day or more) or a DateTime. The page's table and Fude.Test read it.
  @spec table(map()) :: {[String.t()], [[term()]]}
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
       when is_integer(value) and unit in @days, do: day(value)

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
        color_words(scales["color"])
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

  defp color_words(_scale), do: nil

  defp plain(value, %{"type" => "time", "unit" => "day"}) when is_integer(value),
    do: value |> div(86_400_000) |> then(&Date.add(~D[1970-01-01], &1)) |> Date.to_iso8601()

  defp plain(value, %{"type" => "time"}) when is_integer(value),
    do: value |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601()

  defp plain(value, _scale) when is_float(value), do: :erlang.float_to_binary(value, [:short])
  defp plain(value, _scale), do: to_string(value)
end
