defmodule Fude.Data do
  @moduledoc """
  The data of a chart, in columns: each field with its type and its
  values, in the order of the rows.

  Fude takes:

    * a list of maps, with atom or string keys;
    * a map of `:columns` (names) and `:rows` (lists of values in the
      columns' order), as a query result has them (`Postgrex.Result`,
      `Lotus.Result`), with atom or string keys.

  The values become those the browser draws: a `Decimal` a number, a
  `Date`, `NaiveDateTime` or `DateTime` a time (milliseconds since 1970,
  a date at its midnight in UTC), and anything else that is not a number
  text. `nil` stays: it is a gap.
  """

  @compile {:no_warn_undefined, Decimal}

  @type type :: :number | :time | :category

  @type field :: %{name: String.t(), type: type(), unit: :day | :month | :year | nil}

  @type t :: %__MODULE__{
          names: [String.t()],
          fields: [field()],
          columns: %{String.t() => [term()]},
          count: non_neg_integer()
        }

  defstruct names: [], fields: [], columns: %{}, count: 0

  @doc """
  The data in columns. With `only` (names), it reads only those fields: a
  chart reads the few it draws of a query's many. Raises an
  `ArgumentError` when the data is none of the forms above.
  """
  @spec new(term(), [String.t()] | nil) :: t()
  def new(data, only \\ nil)
  def new(%__MODULE__{} = data, _only), do: data
  def new(nil, _only), do: %__MODULE__{}

  def new(%{columns: columns, rows: rows}, only) when is_list(columns) and is_list(rows),
    do: from_rows(Enum.map(columns, &to_string/1), rows, only)

  def new(%{"columns" => columns, "rows" => rows}, only) when is_list(columns) and is_list(rows),
    do: from_rows(Enum.map(columns, &to_string/1), rows, only)

  def new(rows, only) when is_list(rows) do
    # The fields: every key of every row, by its name, with the key that
    # the rows have (an atom or a string), in the order of their names.
    # Merging the rows gives every key of every row, fast.
    keys =
      rows
      |> Enum.reduce(%{}, fn
        row, acc when is_map(row) and not is_struct(row) ->
          Map.merge(acc, row)

        row, _acc ->
          raise ArgumentError,
                "Fude: each row of a chart's data is a map, got: #{inspect(row, limit: 5)}"
      end)
      |> Map.keys()
      |> Map.new(&{to_string(&1), &1})

    names = keys |> Map.keys() |> Enum.sort()

    columns =
      Map.new(read(names, only), fn name -> {name, key_column(rows, Map.fetch!(keys, name))} end)

    build(names, columns, length(rows))
  end

  def new(other, _only) do
    raise ArgumentError,
          "Fude: the data of a chart is a list of maps or a map of :columns and :rows, got: #{inspect(other, limit: 5)}"
  end

  # A field's values, by its key; a row with the other form of the key (a
  # string where most have an atom) is read by that.
  defp key_column(rows, key) do
    other = if is_atom(key), do: Atom.to_string(key), else: String.to_existing_atom(key)

    Enum.map(rows, fn
      %{^key => value} -> value
      row -> Map.get(row, other)
    end)
  rescue
    ArgumentError -> Enum.map(rows, &Map.get(&1, key))
  end

  # The rows of a query result, turned into columns in one pass.
  defp from_rows(names, rows, only) do
    wanted = MapSet.new(read(names, only))

    columns =
      case rows do
        [] -> List.duplicate([], length(names))
        rows -> rows |> Enum.map(&List.to_tuple/1) |> transpose(length(names))
      end

    columns =
      names
      |> Enum.zip(columns)
      |> Enum.filter(fn {name, _values} -> MapSet.member?(wanted, name) end)
      |> Map.new()

    build(names, columns, length(rows))
  end

  defp transpose(tuples, width) do
    for index <- 0..(width - 1)//1 do
      Enum.map(tuples, &if(tuple_size(&1) > index, do: elem(&1, index)))
    end
  end

  defp read(names, nil), do: names
  defp read(names, only), do: Enum.filter(names, &(&1 in only))

  defp build(names, columns, count) do
    {fields, columns} =
      names
      |> Enum.filter(&Map.has_key?(columns, &1))
      |> Enum.map_reduce(columns, fn name, columns ->
        {field, values} = normalize(name, Map.fetch!(columns, name))
        {field, Map.put(columns, name, values)}
      end)

    %__MODULE__{names: names, fields: fields, columns: columns, count: count}
  end

  defp normalize(name, values) do
    type = infer(values)
    unit = if type == :time, do: date_unit(values)
    {%{name: name, type: type, unit: unit}, Enum.map(values, &value(&1, type))}
  end

  # The unit of a column of dates: a year when every date is a first of
  # January, a month when each is a first of a month, else a day. Times of
  # day have none.
  defp date_unit(values) do
    dates = Enum.reject(values, &is_nil/1)

    cond do
      not Enum.all?(dates, &is_struct(&1, Date)) -> nil
      dates != [] and Enum.all?(dates, &(&1.day == 1 and &1.month == 1)) -> :year
      dates != [] and Enum.all?(dates, &(&1.day == 1)) -> :month
      true -> :day
    end
  end

  defp infer(values) do
    Enum.reduce_while(values, nil, fn
      nil, type -> {:cont, type}
      value, type -> {:cont, merge(type, kind(value))} |> stop_on_category()
    end) || :category
  end

  defp stop_on_category({:cont, :category}), do: {:halt, :category}
  defp stop_on_category(other), do: other

  defp kind(value) when is_number(value), do: :number
  defp kind(%{__struct__: Decimal}), do: :number
  defp kind(%Date{}), do: :time
  defp kind(%NaiveDateTime{}), do: :time
  defp kind(%DateTime{}), do: :time
  defp kind(_value), do: :category

  defp merge(nil, kind), do: kind
  defp merge(kind, kind), do: kind
  defp merge(_type, _kind), do: :category

  @doc false
  # A value as the browser draws it, in a column of a type.
  def value(nil, _type), do: nil
  def value(value, :number) when is_number(value), do: value
  def value(%{__struct__: Decimal} = value, :number), do: Decimal.to_float(value)
  def value(%Date{} = date, :time), do: Date.diff(date, ~D[1970-01-01]) * 86_400_000
  def value(%DateTime{} = time, :time), do: DateTime.to_unix(time, :millisecond)

  def value(%NaiveDateTime{} = time, :time),
    do: time |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:millisecond)

  def value(value, :category) when is_binary(value), do: value
  def value(value, :category) when is_atom(value), do: Atom.to_string(value)
  def value(%Date{} = date, :category), do: Date.to_iso8601(date)
  def value(%NaiveDateTime{} = time, :category), do: NaiveDateTime.to_iso8601(time)
  def value(%DateTime{} = time, :category), do: DateTime.to_iso8601(time)
  def value(%{__struct__: Decimal} = value, :category), do: Decimal.to_string(value, :normal)
  def value(value, :category) when is_number(value), do: to_string(value)
  def value(value, :category), do: binary_or_inspect(value)

  defp binary_or_inspect(value) do
    case String.Chars.impl_for(value) do
      nil -> inspect(value)
      _impl -> to_string(value)
    end
  end

  @doc "The field of a name, or `nil`."
  @spec field(t(), String.t()) :: field() | nil
  def field(%__MODULE__{fields: fields}, name), do: Enum.find(fields, &(&1.name == name))

  @doc "The rows whose field has a value."
  @spec where(t(), String.t(), term()) :: t()
  def where(%__MODULE__{} = data, name, value) do
    keep = data |> column(name) |> Enum.map(&(&1 == value))

    columns =
      Map.new(data.columns, fn {field, values} ->
        {field, values |> Enum.zip(keep) |> Enum.filter(&elem(&1, 1)) |> Enum.map(&elem(&1, 0))}
      end)

    %{data | columns: columns, count: Enum.count(keep, & &1)}
  end

  @doc "The names of the fields, in order."
  @spec names(t()) :: [String.t()]
  def names(%__MODULE__{names: names}), do: names

  @doc "The values of a field."
  @spec column(t(), String.t()) :: [term()]
  def column(%__MODULE__{columns: columns}, name), do: Map.get(columns, name, [])

  @doc "The data as rows: a list of maps with string keys, as `Fude.Spec.dump/2` puts it."
  @spec rows(term()) :: [map()]
  def rows(data) do
    %__MODULE__{} = data = new(data)
    names = names(data)

    if data.count == 0 do
      []
    else
      names
      |> Enum.map(&Map.fetch!(data.columns, &1))
      |> Enum.zip()
      |> Enum.map(fn tuple -> names |> Enum.zip(Tuple.to_list(tuple)) |> Map.new() end)
    end
  end
end
