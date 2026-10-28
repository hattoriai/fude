defmodule Fude.Layer do
  @moduledoc """
  One layer of a chart: a kind (`:bar`, `:line`...), its channels and its
  options. A chart has one layer, or several drawn one over the other
  (`Fude.layers/2`).
  """

  alias Fude.Channel

  @type kind ::
          :bar
          | :line
          | :area
          | :scatter
          | :bubble
          | :pie
          | :donut
          | :histogram
          | :heatmap
          | :rule
          | :text
          | :sparkline
          | :number
          | :trend
          | :progress
          | :waterfall
          | :funnel
          | :gauge
          | :choropleth
          | :bubble_map
          | :timeline
          | :boxplot
          | :candlestick
          | :treemap
          | :radar
          | :radial_bar

  @type t :: %__MODULE__{
          id: String.t() | nil,
          kind: kind(),
          channels: %{atom() => Channel.t()},
          options: map()
        }

  defstruct [:id, :kind, channels: %{}, options: %{}]

  # Where a single value sits in its box: centered and sized to it, as a
  # tile of a dashboard, or at the start, as a number inline in a page.
  @align {:in, [:center, :start]}

  @tips [:change, :share, :rank, :history]

  # Each kind: the channels it takes, those it needs, and its options with
  # the check of each value.
  @kinds %{
    bar: %{
      channels: [:x, :y, :color, :opacity, :tooltip, :detail],
      needs: [:x, :y],
      options: [horizontal: :boolean, labels: :boolean]
    },
    line: %{
      channels: [:x, :y, :color, :opacity, :tooltip, :detail],
      needs: [:x, :y],
      options: [curve: {:in, [:linear, :monotone, :step]}, points: :boolean, labels: :boolean]
    },
    area: %{
      channels: [:x, :y, :color, :opacity, :tooltip, :detail],
      needs: [:x, :y],
      options: [curve: {:in, [:linear, :monotone, :step]}, labels: :boolean]
    },
    scatter: %{
      channels: [:x, :y, :color, :size, :shape, :opacity, :tooltip, :detail],
      needs: [:x, :y],
      options: [connect: :boolean, labels: :boolean]
    },
    bubble: %{
      channels: [:x, :y, :color, :size, :opacity, :tooltip, :detail],
      needs: [:x, :y, :size],
      options: [connect: :boolean, labels: :boolean]
    },
    pie: %{
      channels: [:value, :color, :tooltip],
      needs: [:value, :color],
      options: [labels: :boolean]
    },
    donut: %{
      channels: [:value, :color, :tooltip],
      needs: [:value, :color],
      options: [labels: :boolean, inner: :ratio]
    },
    histogram: %{
      channels: [:x, :color, :tooltip],
      needs: [:x],
      options: [bins: :count]
    },
    heatmap: %{channels: [:x, :y, :color, :tooltip], needs: [:x, :y], options: [labels: :boolean]},
    rule: %{channels: [:x, :y, :color], needs: [], options: [label: :string, dashed: :boolean]},
    text: %{channels: [:x, :y, :text, :color], needs: [:text], options: []},
    sparkline: %{
      channels: [:x, :y],
      needs: [:x, :y],
      options: [
        curve: {:in, [:linear, :monotone, :step]},
        area: :boolean,
        points: {:in, [:last, :extremes, false]},
        value: :boolean
      ]
    },
    number: %{
      channels: [:value, :spark],
      needs: [:value],
      options: [label: :string, align: @align]
    },
    trend: %{
      channels: [:value, :compare, :spark],
      needs: [:value],
      options: [label: :string, align: @align]
    },
    progress: %{
      channels: [:value],
      needs: [:value],
      options: [label: :string, goal: :number, align: @align]
    },
    waterfall: %{
      channels: [:x, :y, :tooltip],
      needs: [:x, :y],
      options: [total: :string, start: :string, labels: :boolean]
    },
    funnel: %{
      channels: [:x, :y, :color, :tooltip],
      needs: [:x, :y],
      options: [step: :boolean, labels: {:in, [:inside, :outside, false]}]
    },
    gauge: %{
      channels: [:value],
      needs: [:value],
      options: [label: :string, min: :number, max: :number, target: :number, align: @align]
    },
    choropleth: %{
      channels: [:region, :color, :tooltip],
      needs: [:region, :color],
      options: [map: :string]
    },
    bubble_map: %{
      channels: [:region, :size, :color, :tooltip],
      needs: [:region, :size],
      options: [map: :string]
    },
    timeline: %{
      channels: [:y, :x, :x2, :color, :tooltip],
      needs: [:y, :x, :x2],
      options: []
    },
    boxplot: %{channels: [:x, :y], needs: [:x, :y], options: [outliers: :boolean]},
    candlestick: %{
      channels: [:x, :open, :high, :low, :close, :tooltip],
      needs: [:x, :open, :high, :low, :close],
      options: []
    },
    treemap: %{
      channels: [:name, :value, :color, :tooltip],
      needs: [:name, :value],
      options: [labels: :boolean]
    },
    radar: %{channels: [:x, :y, :color, :tooltip], needs: [:x, :y], options: [labels: :boolean]},
    radial_bar: %{
      channels: [:x, :y, :tooltip],
      needs: [:x, :y],
      options: [max: :number, labels: :boolean]
    }
  }

  @doc false
  def kinds, do: Map.keys(@kinds)

  @doc false
  def kind_spec(kind), do: Map.fetch!(@kinds, kind)

  @doc """
  A layer of a kind, from the keyword list that the functions of `Fude`
  take: channels and options. Raises an `ArgumentError` that says what is
  wrong: an unknown key names the keys of the kind.
  """
  @spec new(kind(), keyword()) :: t()
  def new(kind, opts) do
    spec = Map.get(@kinds, kind) || raise ArgumentError, "Fude: unknown kind #{inspect(kind)}"

    layer =
      Enum.reduce(opts, %__MODULE__{kind: kind}, fn {key, value}, layer ->
        cond do
          key in spec.channels and key == :tooltip ->
            put_tooltip(layer, value)

          key in spec.channels ->
            %{layer | channels: Map.put(layer.channels, key, Channel.new(key, value))}

          Keyword.has_key?(spec.options, key) ->
            %{
              layer
              | options: Map.put(layer.options, key, option!(kind, key, spec.options[key], value))
            }

          true ->
            raise ArgumentError, unknown(kind, key, spec)
        end
      end)

    case Enum.reject(spec.needs, &Map.has_key?(layer.channels, &1)) do
      [] -> stages(layer)
      missing -> raise ArgumentError, "Fude: a #{kind} chart needs #{list(missing)}"
    end
  end

  # A funnel's `color: :stage` colors each stage: its color is its x.
  defp stages(
         %__MODULE__{
           kind: :funnel,
           channels: %{color: %Channel{field: "stage"} = color} = channels
         } = layer
       ) do
    %{x: x} = channels

    if x.field != "stage" and color == Channel.new(:color, :stage),
      do: %{layer | channels: %{channels | color: %Channel{field: x.field}}},
      else: layer
  end

  defp stages(layer), do: layer

  defp put_tooltip(layer, value) do
    {fields, tips} = tooltip(value)

    channels =
      if fields == [], do: layer.channels, else: Map.put(layer.channels, :tooltip, fields)

    options = if tips == %{}, do: layer.options, else: Map.put(layer.options, :tips, tips)
    %{layer | channels: channels, options: options}
  end

  @doc false
  # What a tooltip can add to a mark's values: its change from the point
  # before, its share of the whole, its rank, and a small history.
  def tips, do: @tips

  # A tooltip's fields, and what it adds (`change: true`), from a list of
  # both (`[:plan, change: true]`), a list of fields, a field, or a field's
  # full form.
  defp tooltip(list) when is_list(list) and list != [] do
    {tips, rest} = Enum.split_with(list, &tip?/1)
    tips = Map.new(tips)

    fields =
      cond do
        rest == [] -> []
        is_tuple(hd(rest)) and Keyword.keyword?(rest) -> [Channel.new(:tooltip, rest)]
        true -> Enum.map(rest, &Channel.new(:tooltip, &1))
      end

    {fields, tips}
  end

  defp tooltip(field), do: {[Channel.new(:tooltip, field)], %{}}

  defp tip?({key, value}) when key in @tips, do: is_boolean(value)
  defp tip?(_entry), do: false

  @doc false
  # Checks an option's value: the functions of Fude raise, a loaded spec
  # gives the error.
  def check_option(:boolean, value), do: is_boolean(value)
  def check_option(:string, value), do: is_binary(value)
  def check_option(:number, value), do: is_number(value)
  def check_option(:count, value), do: is_integer(value) and value > 0 and value <= 500
  def check_option(:ratio, value), do: is_number(value) and value >= 0 and value < 1
  def check_option({:in, values}, value), do: value in values

  defp option!(kind, key, check, value) do
    if check_option(check, value) do
      value
    else
      raise ArgumentError,
            "Fude: #{inspect(key)} of a #{kind} chart must be #{describe(check)}, got: #{inspect(value)}"
    end
  end

  @doc false
  def describe(:boolean), do: "true or false"
  def describe(:string), do: "a string"
  def describe(:number), do: "a number"
  def describe(:count), do: "a whole number from 1 to 500"
  def describe(:ratio), do: "a number from 0 up to 1"
  def describe({:in, values}), do: "one of " <> Enum.map_join(values, ", ", &inspect/1)

  defp unknown(kind, key, spec) do
    keys = spec.channels ++ Keyword.keys(spec.options)

    "Fude: a #{kind} chart has no #{inspect(key)}; it takes #{list(keys)}" <>
      Fude.Names.suggest(key, keys)
  end

  defp list(keys), do: Enum.map_join(keys, ", ", &inspect/1)
end
