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
          | :choropleth
          | :bubble_map

  @type t :: %__MODULE__{
          kind: kind(),
          channels: %{atom() => Channel.t()},
          options: map()
        }

  defstruct [:kind, channels: %{}, options: %{}]

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
      options: []
    },
    bubble: %{
      channels: [:x, :y, :color, :size, :opacity, :tooltip, :detail],
      needs: [:x, :y, :size],
      options: []
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
      options: [curve: {:in, [:linear, :monotone, :step]}]
    },
    number: %{channels: [:value], needs: [:value], options: [label: :string]},
    trend: %{channels: [:value, :compare], needs: [:value], options: [label: :string]},
    progress: %{channels: [:value], needs: [:value], options: [label: :string, goal: :number]},
    choropleth: %{
      channels: [:region, :color, :tooltip],
      needs: [:region, :color],
      options: [map: :string]
    },
    bubble_map: %{
      channels: [:region, :size, :color, :tooltip],
      needs: [:region, :size],
      options: [map: :string]
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
            %{layer | channels: Map.put(layer.channels, :tooltip, tooltip(value))}

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
      [] -> layer
      missing -> raise ArgumentError, "Fude: a #{kind} chart needs #{list(missing)}"
    end
  end

  defp tooltip(fields) when is_list(fields) and not is_tuple(hd(fields)),
    do: Enum.map(fields, &Channel.new(:tooltip, &1))

  defp tooltip(field), do: [Channel.new(:tooltip, field)]

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
