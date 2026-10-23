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

  @type field :: %{name: String.t(), type: type(), unit: :day | nil}

  @type t :: %__MODULE__{
          fields: [field()],
          columns: %{String.t() => [term()]},
          count: non_neg_integer()
        }

  defstruct fields: [], columns: %{}, count: 0

  @doc "The data in columns. Raises an `ArgumentError` when it is none of the forms above."
  @spec new(term()) :: t()
  def new(%__MODULE__{} = data), do: data
  def new(nil), do: %__MODULE__{}

  def new(%{columns: columns, rows: rows}) when is_list(columns) and is_list(rows),
    do: from_rows(Enum.map(columns, &to_string/1), rows)

  def new(%{"columns" => columns, "rows" => rows}) when is_list(columns) and is_list(rows),
    do: from_rows(Enum.map(columns, &to_string/1), rows)

  def new(rows) when is_list(rows) do
    names =
      rows
      |> Enum.reduce({[], MapSet.new()}, fn row, acc -> Enum.reduce(keys(row), acc, &add_name/2) end)
      |> elem(0)
      |> Enum.reverse()

    columns =
      Map.new(names, fn name ->
        {name, Enum.map(rows, &fetch(&1, name))}
      end)

    build(names, columns, length(rows))
  end

  def new(other) do
    raise ArgumentError,
          "Fude: the data of a chart is a list of maps or a map of :columns and :rows, got: #{inspect(other, limit: 5)}"
  end

  defp keys(row) when is_map(row), do: row |> Map.keys() |> Enum.sort_by(&to_string/1)

  defp keys(row),
    do: raise(ArgumentError, "Fude: each row of a chart's data is a map, got: #{inspect(row, limit: 5)}")

  defp add_name(key, {names, seen}) do
    name = to_string(key)
    if MapSet.member?(seen, name), do: {names, seen}, else: {[name | names], MapSet.put(seen, name)}
  end

  # A row's value of a field, by its string key or its atom key.
  defp fetch(row, name) do
    case Map.fetch(row, name) do
      {:ok, value} ->
        value

      :error ->
        Enum.find_value(row, fn {key, value} -> if is_atom(key) and Atom.to_string(key) == name, do: {value} end)
        |> case do
          {value} -> value
          nil -> nil
        end
    end
  end

  defp from_rows(names, rows) do
    columns =
      names
      |> Enum.with_index()
      |> Map.new(fn {name, index} -> {name, Enum.map(rows, &Enum.at(List.wrap(&1), index))} end)

    build(names, columns, length(rows))
  end

  defp build(names, columns, count) do
    {fields, columns} =
      Enum.map_reduce(names, columns, fn name, columns ->
        {field, values} = normalize(name, Map.fetch!(columns, name))
        {field, Map.put(columns, name, values)}
      end)

    %__MODULE__{fields: fields, columns: columns, count: count}
  end

  defp normalize(name, values) do
    type = infer(values)
    unit = if type == :time and Enum.all?(values, &(is_nil(&1) or is_struct(&1, Date))), do: :day
    {%{name: name, type: type, unit: unit}, Enum.map(values, &value(&1, type))}
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

  @doc "The names of the fields, in order."
  @spec names(t()) :: [String.t()]
  def names(%__MODULE__{fields: fields}), do: Enum.map(fields, & &1.name)

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
