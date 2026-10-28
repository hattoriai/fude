defmodule Fude.Channel do
  @moduledoc """
  What a channel of a chart shows: the field of the data it reads, and
  how. `x`, `y`, `color` and `size` are channels.

  A channel is given in a short form or in full:

      Fude.bar(sales, x: :region, y: :revenue)
      Fude.bar(sales, x: :region, y: {:sum, :revenue})
      Fude.line(visits, x: {:month, :day}, y: {:count, :id})
      Fude.histogram(orders, x: {:bin, :total})
      Fude.bar(sales, x: :region, y: [field: :revenue, aggregate: :sum, format: :compact])
      Fude.rule(y: 1000)

    * an atom or a string is a field;
    * `{aggregate, field}` aggregates the field: `:count`, `:sum`, `:mean`,
      `:median`, `:min`, `:max` or `:distinct`;
    * `{unit, field}` takes a unit of a time: `:year`, `:quarter`,
      `:month`, `:week`, `:day`, `:hour` or `:minute`;
    * `{:bin, field}` puts the numbers of a field in bins;
    * a number is a constant, as the height of a rule;
    * a keyword list is the full form, with the keys below.

  ## Keys

    * `:field` - the field of the data.
    * `:type` - `:number`, `:time`, `:category` or `:ordinal`; learned from
      the data when not given.
    * `:aggregate` - see above.
    * `:time` - a unit of a time, see above.
    * `:bin` - `true`, or a keyword list with `:count` (about how many bins)
      or `:step` (the width of a bin).
    * `:sort` - the order of a field's categories: `:ascending`,
      `:descending`, `:x`, `:y`, `:"-x"` or `:"-y"` (by another channel,
      the minus for descending), or a list of the categories in order.
    * `:format` - how the browser writes the values: `:number`, `:integer`,
      `:percent`, `:compact`, `{:currency, "EUR"}`, `:bytes` (1 KB is
      1,024 bytes), `:decimal_bytes` (1 KB is 1,000 bytes, as networks and
      disks count them, so that the ticks of a log scale are round), or a
      unit of a time for times.
    * `:digits` - how many decimals the values are written with, from 0 to
      20, for `:number`, `:compact`, `:percent`, bytes and currencies:
      `[field: :revenue, format: :number, digits: 0]` writes 6,893,914. Not
      given, `:number` keeps a value's decimals up to 2, `:compact` and
      `:percent` write up to 1, and a currency 2 under 1,000 and none from
      there. An axis's ticks take the decimals their step needs.
    * `:suffix` - words written after every value, on the axis, in the
      labels and in the tooltip: `[field: :speedup, suffix: "×"]` writes
      24.2×, `[field: :rate, format: :decimal_bytes, suffix: "/s"]` writes
      618.6 MB/s.
    * `:scheme` - the colors of a `color` channel, by name: sequential
      `:blue` (the default), `:green`, `:orange`, `:purple`, `:gray`,
      `:viridis`; diverging `:red_blue`, `:red_green` (around `:mid`);
      categorical `:categorical` (the default) and `:okabe_ito`. Or a list
      of colors (`["#0b6e4f", "#f2c14e", "#d1495b"]`): a ramp for numbers,
      a color for each category, in order.
    * `:mid` - the value at the middle of a diverging scheme: 0 when not
      given.
    * `:highlight` - the series of a `color` channel that matter: a value
      or a list of them (`highlight: "Online"`). They keep their colors and
      are drawn over the others, which are gray (`--fude-context`), as a
      graphics desk sets one line against the rest.
    * `:title` - the title of the axis or the legend; the field's name when
      not given, `false` for none.
    * `:scale` - a keyword list: `:type` (`:linear`, `:log`, `:sqrt`),
      `:domain` (`[min, max]`, or the categories), `:zero` (whether a
      number scale starts at zero), `:nice`.
    * `:stack` - `:zero` (the default of bars and areas with a color),
      `:normalize` (to 100%), `:center` or `false`.
    * `:value` - a constant instead of a field.
    * `:axis` - `:right` for a `y` of its own scale, on an axis at the
      right of the plot: a layer of other units over another, as a line
      of revenue over bars of orders (`Fude.layers/3`). `:left` is the
      default.
  """

  @type aggregate :: :count | :sum | :mean | :median | :min | :max | :distinct
  @type time_unit :: :year | :quarter | :month | :week | :day | :hour | :minute
  @type type :: :number | :time | :category | :ordinal

  @type t :: %__MODULE__{
          field: String.t() | nil,
          type: type() | nil,
          aggregate: aggregate() | nil,
          time: time_unit() | nil,
          bin: boolean() | map() | nil,
          sort: atom() | [term()] | nil,
          format: atom() | {atom(), String.t()} | nil,
          digits: non_neg_integer() | nil,
          suffix: String.t() | nil,
          scheme: atom() | [String.t()] | nil,
          mid: number() | nil,
          highlight: [term()] | nil,
          title: String.t() | false | nil,
          scale: map() | nil,
          stack: atom() | false | nil,
          value: term(),
          axis: :left | :right | nil
        }

  defstruct [
    :field,
    :type,
    :aggregate,
    :time,
    :bin,
    :sort,
    :format,
    :digits,
    :suffix,
    :scheme,
    :mid,
    :highlight,
    :title,
    :scale,
    :stack,
    :value,
    :axis
  ]

  @aggregates [:count, :sum, :mean, :median, :min, :max, :distinct]
  @time_units [:year, :quarter, :month, :week, :day, :hour, :minute]
  @types [:number, :time, :category, :ordinal]
  @sorts [:ascending, :descending, :x, :y, :"-x", :"-y"]
  @formats [
    :number,
    :integer,
    :percent,
    :compact,
    :bytes,
    :decimal_bytes,
    :duration | @time_units
  ]
  @stacks [:zero, :normalize, :center]
  @scale_types [:linear, :log, :sqrt]
  @axes [:left, :right]
  @sequential_schemes [:blue, :green, :orange, :purple, :gray, :viridis]
  @diverging_schemes [:red_blue, :red_green]
  @categorical_schemes [:categorical, :okabe_ito]
  @schemes @sequential_schemes ++ @diverging_schemes ++ @categorical_schemes

  @doc false
  def aggregates, do: @aggregates
  @doc false
  def time_units, do: @time_units
  @doc false
  def types, do: @types
  @doc false
  def sorts, do: @sorts
  @doc false
  def formats, do: @formats
  @doc false
  def stacks, do: @stacks
  @doc false
  def scale_types, do: @scale_types
  @doc false
  def axes, do: @axes
  @doc false
  def schemes, do: @schemes
  @doc false
  def diverging?(scheme), do: scheme in @diverging_schemes

  @doc false
  # A color of a scheme's list: a hex color, or a CSS color function of
  # plain characters, so that it is safe in a style.
  def color?(color),
    do:
      is_binary(color) and byte_size(color) <= 64 and
        color =~ ~r/^(#[0-9a-fA-F]{3,8}|[a-z]+\([0-9a-zA-Z.,%\s\/-]*\)|[a-z]+)$/

  @doc false
  # The series a channel highlights: a value or a list of them, each text,
  # a number or an atom (as text).
  def highlights(value) when is_list(value) and value != [] do
    values = Enum.map(value, &highlight_value/1)
    if Enum.any?(values, &(&1 == :error)), do: :error, else: {:ok, values}
  end

  def highlights(value) do
    case highlight_value(value) do
      :error -> :error
      single -> {:ok, [single]}
    end
  end

  defp highlight_value(value) when is_binary(value) or is_number(value), do: value

  defp highlight_value(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  defp highlight_value(_value), do: :error

  @doc false
  # Words after a value: a short string, written as text.
  def suffix?(suffix), do: is_binary(suffix) and suffix != "" and String.length(suffix) <= 16

  @doc false
  def colors?(list), do: is_list(list) and length(list) >= 2 and Enum.all?(list, &color?/1)

  @doc """
  A channel from its short form or its full form (see above). Raises an
  `ArgumentError` that names the channel and the value when it is neither.
  """
  @spec new(atom(), term()) :: t()
  def new(_name, %__MODULE__{} = channel), do: channel

  def new(_name, field) when is_atom(field) and not is_boolean(field) and not is_nil(field),
    do: %__MODULE__{field: Atom.to_string(field)}

  def new(_name, field) when is_binary(field), do: %__MODULE__{field: field}
  def new(_name, value) when is_number(value), do: %__MODULE__{value: value}
  def new(name, {:bin, field}), do: %__MODULE__{field: field!(name, field), bin: true}

  def new(name, {aggregate, field}) when aggregate in @aggregates,
    do: %__MODULE__{field: field!(name, field), aggregate: aggregate}

  def new(name, {unit, field}) when unit in @time_units,
    do: %__MODULE__{field: field!(name, field), time: unit}

  def new(name, options) when is_list(options) do
    if Keyword.keyword?(options) and options != [] do
      Enum.reduce(options, %__MODULE__{}, &put(name, &2, &1))
    else
      raise ArgumentError, bad(name, options)
    end
  end

  def new(name, other), do: raise(ArgumentError, bad(name, other))

  defp put(name, channel, {:field, field}), do: %{channel | field: field!(name, field)}
  defp put(_name, channel, {:type, type}) when type in @types, do: %{channel | type: type}

  defp put(_name, channel, {:aggregate, aggregate}) when aggregate in @aggregates,
    do: %{channel | aggregate: aggregate}

  defp put(_name, channel, {:time, unit}) when unit in @time_units, do: %{channel | time: unit}
  defp put(_name, channel, {:bin, bin}) when is_boolean(bin), do: %{channel | bin: bin}

  defp put(name, channel, {:bin, bin}) when is_list(bin) do
    case bin do
      [count: count] when is_integer(count) and count > 0 -> %{channel | bin: %{count: count}}
      [step: step] when is_number(step) and step > 0 -> %{channel | bin: %{step: step}}
      _ -> raise ArgumentError, bad_key(name, :bin, bin, "count: n or step: n")
    end
  end

  defp put(_name, channel, {:sort, sort}) when sort in @sorts or is_list(sort),
    do: %{channel | sort: sort}

  defp put(_name, channel, {:format, format}) when format in @formats,
    do: %{channel | format: format}

  defp put(_name, channel, {:format, {:currency, code}}) when is_binary(code),
    do: %{channel | format: {:currency, code}}

  defp put(_name, channel, {:digits, digits}) when digits in 0..20,
    do: %{channel | digits: digits}

  defp put(name, channel, {:suffix, suffix}) do
    if suffix?(suffix),
      do: %{channel | suffix: suffix},
      else: raise(ArgumentError, bad_key(name, :suffix, suffix, expected(:suffix)))
  end

  defp put(_name, channel, {:scheme, scheme}) when scheme in @schemes,
    do: %{channel | scheme: scheme}

  defp put(name, channel, {:scheme, scheme}) when is_list(scheme) do
    if colors?(scheme),
      do: %{channel | scheme: scheme},
      else: raise(ArgumentError, bad_key(name, :scheme, scheme, expected(:scheme)))
  end

  defp put(_name, channel, {:mid, mid}) when is_number(mid), do: %{channel | mid: mid}

  defp put(name, channel, {:highlight, highlight}) do
    case highlights(highlight) do
      {:ok, values} -> %{channel | highlight: values}
      :error -> raise ArgumentError, bad_key(name, :highlight, highlight, expected(:highlight))
    end
  end

  defp put(_name, channel, {:title, title}) when is_binary(title) or title == false,
    do: %{channel | title: title}

  defp put(name, channel, {:scale, scale}) when is_list(scale),
    do: %{channel | scale: scale(name, scale)}

  defp put(_name, channel, {:stack, stack}) when stack in @stacks or stack == false,
    do: %{channel | stack: stack}

  defp put(_name, channel, {:value, value}), do: %{channel | value: value}
  defp put(_name, channel, {:axis, axis}) when axis in @axes, do: %{channel | axis: axis}

  defp put(name, _channel, {key, value}) do
    raise ArgumentError, bad_key(name, key, value, expected(key))
  end

  defp scale(name, options) do
    Map.new(options, fn
      {:type, type} when type in @scale_types -> {:type, type}
      {:domain, domain} when is_list(domain) -> {:domain, domain}
      {:zero, zero} when is_boolean(zero) -> {:zero, zero}
      {:nice, nice} when is_boolean(nice) -> {:nice, nice}
      {key, value} -> raise ArgumentError, bad_key(name, {:scale, key}, value, "see Fude.Channel")
    end)
  end

  defp field!(_name, field) when is_binary(field), do: field

  defp field!(_name, field) when is_atom(field) and not is_boolean(field) and not is_nil(field),
    do: Atom.to_string(field)

  defp field!(name, field),
    do:
      raise(
        ArgumentError,
        "Fude: the field of #{inspect(name)} must be an atom or a string, got: #{inspect(field)}"
      )

  defp expected(:type), do: Enum.map_join(@types, ", ", &inspect/1)
  defp expected(:aggregate), do: Enum.map_join(@aggregates, ", ", &inspect/1)
  defp expected(:time), do: Enum.map_join(@time_units, ", ", &inspect/1)
  defp expected(:sort), do: Enum.map_join(@sorts, ", ", &inspect/1) <> " or a list"
  defp expected(:stack), do: Enum.map_join(@stacks, ", ", &inspect/1) <> " or false"
  defp expected(:format), do: Enum.map_join(@formats, ", ", &inspect/1) <> " or {:currency, code}"
  defp expected(:digits), do: "a whole number from 0 to 20"
  defp expected(:suffix), do: "a string of 1 to 16 characters"

  defp expected(:scheme),
    do: Enum.map_join(@schemes, ", ", &inspect/1) <> ", or a list of two colors or more"

  defp expected(:mid), do: "a number"
  defp expected(:highlight), do: "a value or a list of values (text or numbers)"
  defp expected(:title), do: "a string or false"
  defp expected(:bin), do: "true, or count: n or step: n"
  defp expected(:axis), do: ":left or :right"

  defp expected(_key),
    do:
      "one of :field, :type, :aggregate, :time, :bin, :sort, :format, :digits, :suffix, " <>
        ":scheme, :mid, :highlight, :title, :scale, :stack, :value, :axis"

  defp bad(name, value) do
    "Fude: #{inspect(name)} must be a field, {aggregate, field}, {unit, field}, {:bin, field}, " <>
      "a number or a keyword list, got: #{inspect(value)}"
  end

  defp bad_key(name, key, value, expected) do
    "Fude: #{inspect(key)} of #{inspect(name)} must be #{expected}, got: #{inspect(value)}"
  end

  @doc "Whether the channel reads a field (and not a constant)."
  @spec field?(t()) :: boolean()
  def field?(%__MODULE__{field: field}), do: is_binary(field)

  @doc "The title of the channel's axis or legend: its own, or its field's name."
  @spec title(t()) :: String.t() | nil
  def title(%__MODULE__{title: false}), do: nil
  def title(%__MODULE__{title: title}) when is_binary(title), do: title
  def title(%__MODULE__{aggregate: :count, field: nil}), do: "Count"
  def title(%__MODULE__{field: nil}), do: nil
  def title(%__MODULE__{aggregate: :count}), do: "Count"
  def title(%__MODULE__{field: field}), do: humanize(field)

  # A field's name as words: "order_total" is "Order total".
  defp humanize(field) do
    case field |> String.replace("_", " ") |> String.trim() do
      "" -> field
      words -> String.upcase(String.first(words)) <> String.slice(words, 1..-1//1)
    end
  end
end
