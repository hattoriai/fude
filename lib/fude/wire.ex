defmodule Fude.Wire do
  @moduledoc """
  The columns of a chart, packed for the browser: smaller, and the same
  numbers when unpacked.

  A column of numbers is sent packed when that is much smaller: each value
  as the steps from the one before it, in a unit common to all of them.
  Days of a time series, each a timestamp of 13 digits, become steps of 0
  and 1:

      [1672531200000, 1672617600000, 1672704000000]
      %{"from" => 1672531200000, "step" => 86400000, "deltas" => [0, 1, 1]}

  A value is `from + step * k`, where `k` is the sum of the deltas up to it;
  `nil` stays `nil` and does not move `k`. A column of floats has
  `"decimals"`, and its values are divided by 10 to that power:

      [1.5, 1.75, 2.0]
      %{"from" => 150, "step" => 25, "decimals" => 2, "deltas" => [0, 1, 1]}

  A column is packed only when unpacking it gives back exactly its values,
  checked as it is packed, so packing can make the data smaller but never
  different. Any other column is sent as it is: a column of words, of
  integers mixed with floats, of numbers too large to add exactly in the
  browser (2^52 and over), or of floats with more than six decimals.

  The browser unpacks the same way (`assets/src/wire.ts`); the shared
  fixture, `test/fixtures/wire.json`, holds the cases both test suites run.
  """

  # Above this, from + step * k could pass 2^53 in the browser, where
  # integers stop being exact.
  @max_int 4_503_599_627_370_496
  @max_decimals 6
  @powers Map.new(0..@max_decimals, &{&1, Integer.pow(10, &1)})

  # Packed only when it is at most this share of the plain column: less
  # gain is not worth the step.
  @worth 0.8

  @doc "The wire with every column it can pack packed: its layers', its tooltips' and its panels'."
  @spec pack(map()) :: map()
  def pack(wire) when is_map(wire), do: each_column(wire, &pack_column/1)

  @doc "The wire with every packed column unpacked: the inverse of `pack/1`."
  @spec unpack(map()) :: map()
  def unpack(wire) when is_map(wire), do: each_column(wire, &unpack_column/1)

  @doc """
  A column, packed when that is smaller and exact (a map), or as it is (a
  list).
  """
  @spec pack_column(list()) :: list() | map()
  def pack_column(values) when is_list(values) do
    with {:ok, ints, decimals} <- integers(values),
         {from, step} <- from_and_step(ints),
         deltas = deltas(ints, from, step),
         true <- worth?(values, ints, deltas, decimals) do
      packed = %{"from" => from, "step" => step, "deltas" => deltas}
      packed = if decimals, do: Map.put(packed, "decimals", decimals), else: packed
      # Checked here, so that a packed column is always the same numbers.
      if same?(unpack_column(packed), values), do: packed, else: values
    else
      _ -> values
    end
  end

  @doc "A column as its values: a packed column unpacked, a list as it is."
  @spec unpack_column(list() | map()) :: list()
  def unpack_column(values) when is_list(values), do: values

  def unpack_column(%{"from" => from, "step" => step, "deltas" => deltas} = packed) do
    divide =
      case packed["decimals"] do
        nil -> fn n -> n end
        decimals -> fn n -> n / Map.fetch!(@powers, decimals) end
      end

    {values, _k} =
      Enum.map_reduce(deltas, 0, fn
        nil, k -> {nil, k}
        delta, k -> {divide.(from + step * (k + delta)), k + delta}
      end)

    values
  end

  # -- Packing -----------------------------------------------------------------

  # The values as integers: themselves (decimals nil), or floats times 10 to
  # the fewest decimals that give each back. Not for words, nor for
  # integers mixed with floats, so that every value comes back as its type.
  defp integers(values) do
    numbers = Enum.reject(values, &is_nil/1)

    cond do
      numbers == [] ->
        :error

      Enum.all?(numbers, &is_integer/1) ->
        if Enum.all?(numbers, &(abs(&1) < @max_int)), do: {:ok, values, nil}, else: :error

      Enum.all?(numbers, &is_float/1) ->
        Enum.find_value(0..@max_decimals, :error, &with_decimals(values, &1))

      true ->
        :error
    end
  end

  defp with_decimals(values, decimals) do
    case scaled(values, Map.fetch!(@powers, decimals)) do
      {:ok, ints} -> {:ok, ints, decimals}
      :error -> nil
    end
  end

  defp scaled(values, power) do
    Enum.reduce_while(values, [], fn
      nil, acc ->
        {:cont, [nil | acc]}

      value, acc ->
        n = round(value * power)
        if abs(n) < @max_int and n / power == value, do: {:cont, [n | acc]}, else: {:halt, :error}
    end)
    |> case do
      :error -> :error
      ints -> {:ok, Enum.reverse(ints)}
    end
  end

  # The first value, and the largest unit that every value is a whole
  # number of steps from it.
  defp from_and_step(ints) do
    [from | _] = numbers = Enum.reject(ints, &is_nil/1)
    step = Enum.reduce(numbers, 0, &Integer.gcd(&1 - from, &2))
    {from, max(step, 1)}
  end

  defp deltas(ints, from, step) do
    {deltas, _k} =
      Enum.map_reduce(ints, 0, fn
        nil, k -> {nil, k}
        n, k -> {div(n - from, step) - k, div(n - from, step)}
      end)

    deltas
  end

  # The sizes as JSON, near enough to choose: the digits of each value,
  # with a float's point.
  defp worth?(values, ints, deltas, decimals) do
    point = if decimals, do: 2, else: 0

    plain =
      Enum.zip_with(values, ints, fn
        nil, _ -> 5
        _value, n -> digits(n) + point
      end)
      |> Enum.sum()

    packed = deltas |> Enum.map(&if(is_nil(&1), do: 5, else: digits(&1))) |> Enum.sum()
    packed + 60 <= plain * @worth
  end

  # Digits, a minus sign and a comma.
  defp digits(n) when n < 0, do: digits(-n) + 1
  defp digits(n), do: count_digits(n, 1) + 1

  defp count_digits(n, count) when n < 10, do: count
  defp count_digits(n, count), do: count_digits(div(n, 10), count + 1)

  # The same values, each as its type: what the browser would draw.
  defp same?([], []), do: true
  defp same?([nil | a], [nil | b]), do: same?(a, b)
  defp same?([x | a], [y | b]) when is_integer(x) and is_integer(y) and x == y, do: same?(a, b)
  defp same?([x | a], [y | b]) when is_float(x) and is_float(y) and x == y, do: same?(a, b)
  defp same?(_a, _b), do: false

  # -- The columns of a wire -----------------------------------------------------

  defp each_column(wire, fun) do
    wire
    |> update_list("layers", &layer(&1, fun))
    |> update_present("facet", fn facet ->
      update_list(facet, "panels", fn panel -> update_list(panel, "layers", &layer(&1, fun)) end)
    end)
  end

  defp layer(layer, fun) do
    layer
    |> update_present("columns", fn columns ->
      Map.new(columns, fn {name, column} -> {name, fun.(column)} end)
    end)
    |> update_list("tooltip", fn tip -> update_present(tip, "values", fun) end)
  end

  defp update_list(map, key, fun) do
    case map do
      %{^key => list} when is_list(list) -> Map.put(map, key, Enum.map(list, fun))
      _ -> map
    end
  end

  defp update_present(map, key, fun) do
    case map do
      %{^key => value} when is_map(value) or is_list(value) -> Map.put(map, key, fun.(value))
      _ -> map
    end
  end
end
