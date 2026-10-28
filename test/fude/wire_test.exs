defmodule Fude.WireTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Fude.Wire

  @day 86_400_000
  @max_int 4_503_599_627_370_496

  # The cases that the browser's wire.ts runs too. FUDE_WRITE_FIXTURES=1
  # writes them again from fixture_cases/0, after a change to the packing.
  @fixture_path "test/fixtures/wire.json"
  @external_resource @fixture_path
  @fixture @fixture_path |> File.read!() |> JSON.decode!()

  # The values a column comes back as, through JSON as the browser gets it.
  defp sent(column), do: column |> JSON.encode!() |> JSON.decode!()

  defp round_trip(column), do: column |> Wire.pack_column() |> sent() |> Wire.unpack_column()

  # The same values, each as its type: an integer is not a float, nil is nil.
  defp assert_same(got, want) do
    assert length(got) == length(want)

    for {g, w, i} <- Enum.zip([got, want, Stream.iterate(0, &(&1 + 1))]) do
      assert (is_integer(g) and is_integer(w) and g == w) or
               (is_float(g) and is_float(w) and g == w) or
               (not is_number(g) and g === w),
             "value #{i}: got #{inspect(g)}, want #{inspect(w)}"
    end
  end

  describe "pack_column/1" do
    test "days as steps of a day from the first" do
      column = for i <- 0..99, do: 1_672_531_200_000 + i * @day

      assert %{"from" => 1_672_531_200_000, "step" => @day, "deltas" => [0 | deltas]} =
               packed = Wire.pack_column(column)

      assert deltas == List.duplicate(1, 99)
      refute Map.has_key?(packed, "decimals")
      assert_same(round_trip(column), column)
    end

    test "the same day for each series, then the next: steps of 0 and 1" do
      column = for i <- 0..299, _series <- 1..4, do: 1_672_531_200_000 + i * @day
      packed = Wire.pack_column(column)

      assert packed["deltas"] |> Enum.uniq() |> Enum.sort() == [0, 1]
      assert byte_size(JSON.encode!(packed)) * 5 < byte_size(JSON.encode!(column))
      assert_same(round_trip(column), column)
    end

    test "floats in a unit of their decimals, and back as floats" do
      column = for i <- 0..199, do: 1.5 + i * 0.25
      assert %{"decimals" => 2, "step" => 25} = Wire.pack_column(column)
      assert_same(round_trip(column), column)
    end

    test "whole floats stay floats" do
      column = for i <- 0..199, do: 1000.0 + i
      assert %{"decimals" => 0} = Wire.pack_column(column)
      assert_same(round_trip(column), column)
    end

    test "nil keeps its place and does not move the count" do
      column =
        for i <- 0..199, do: if(rem(i, 7) == 3, do: nil, else: 1_700_000_000_000 + i * 60_000)

      assert is_map(Wire.pack_column(column))
      assert_same(round_trip(column), column)

      leading = List.duplicate(nil, 5) ++ Enum.drop(column, 5) ++ [nil, nil]
      assert_same(round_trip(leading), leading)
    end

    test "falling and repeating values" do
      column = for i <- 0..199, do: 10_000_000 - div(i, 3) * 1_000
      assert is_map(Wire.pack_column(column))
      assert_same(round_trip(column), column)
    end

    test "a column of one value repeated" do
      column = List.duplicate(1_672_531_200_000, 200)
      assert %{"step" => 1, "deltas" => deltas} = Wire.pack_column(column)
      assert Enum.all?(deltas, &(&1 == 0))
      assert_same(round_trip(column), column)
    end

    test "stays as it is when packing is not much smaller" do
      for column <- [
            [],
            [nil, nil],
            [1_672_531_200_000, 1_672_617_600_000],
            Enum.to_list(0..99),
            # Values with nothing in common: steps as long as the values.
            for(i <- 1..200, do: rem(i * 7_919, 1_000))
          ] do
        assert Wire.pack_column(column) == column
      end
    end

    test "stays as it is when it could not come back exactly" do
      days = for i <- 0..199, do: 1_672_531_200_000 + i * @day

      for column <- [
            # Words, booleans, and integers mixed with floats.
            Enum.map(days, &Integer.to_string/1),
            Enum.map(days, &(rem(&1, 2) == 0)),
            List.replace_at(days, 10, 1_672_531_200_000.0),
            # Too large to add exactly in the browser.
            Enum.map(days, &(&1 + @max_int)),
            Enum.map(days, &(-&1 - @max_int)),
            # More decimals than six, and floats with no short decimals.
            for(i <- 0..199, do: 1.0 + i * 1.0e-7),
            for(i <- 0..199, do: i * 0.1 + 0.2),
            for(i <- 0..199, do: :math.sqrt(i + 2))
          ] do
        assert Wire.pack_column(column) == column
        assert_same(round_trip(column), column)
      end
    end

    test "negative numbers and zero" do
      column = for i <- -100..99, do: i * 1_000_000
      assert is_map(Wire.pack_column(column))
      assert_same(round_trip(column), column)

      floats = for i <- -100..99, do: i * 0.5
      assert_same(round_trip(floats), floats)
    end
  end

  describe "the round trip, through JSON" do
    property "integers and nil" do
      check all(
              column <- list_of(one_of([integer(), integer(-@max_int..@max_int), constant(nil)])),
              max_runs: 300
            ) do
        assert_same(round_trip(column), column)
      end
    end

    property "floats and nil, of any size" do
      check all(column <- list_of(one_of([float(), constant(nil)])), max_runs: 300) do
        assert_same(round_trip(column), column)
      end
    end

    property "floats of a few decimals, as data has them" do
      check all(
              decimals <- integer(0..8),
              start <- integer(-1_000_000..1_000_000),
              steps <- list_of(integer(-50..500), min_length: 50, max_length: 400),
              max_runs: 300
            ) do
        column =
          steps
          |> Enum.scan(start, &(&1 + &2))
          |> Enum.map(&Float.round(&1 / Integer.pow(10, decimals), decimals))

        assert_same(round_trip(column), column)
      end
    end

    property "times of a series: sorted, repeated, with gaps and nil" do
      check all(
              unit <- member_of([1, 1_000, 60_000, 3_600_000, @day, 7 * @day]),
              start <- integer(0..2_000_000_000_000),
              steps <-
                list_of(one_of([integer(0..3), constant(nil)]), min_length: 50, max_length: 400),
              max_runs: 300
            ) do
        {column, _} =
          Enum.map_reduce(steps, start, fn
            nil, t -> {nil, t}
            step, t -> {t + step * unit, t + step * unit}
          end)

        packed = Wire.pack_column(column)
        assert_same(round_trip(column), column)

        if Enum.count(column, &is_integer/1) > 40 and Enum.count(column, &is_nil/1) < 20,
          do: assert(is_map(packed))
      end
    end

    property "packed is never larger as JSON" do
      check all(
              column <-
                one_of([
                  list_of(one_of([integer(), constant(nil)])),
                  list_of(one_of([float(), constant(nil)])),
                  list_of(integer(0..1_000), min_length: 100)
                ]),
              max_runs: 300
            ) do
        packed = Wire.pack_column(column)
        assert byte_size(JSON.encode!(packed)) <= byte_size(JSON.encode!(column))
      end
    end
  end

  describe "pack/1 and unpack/1 of a chart's wire" do
    test "pack the layers' columns and tooltips, nothing else" do
      days = for i <- 0..199, do: 1_672_531_200_000 + i * @day
      categories = for i <- 0..199, do: rem(i, 3)

      wire = %{
        "kind" => "line",
        "scales" => %{"x" => %{"type" => "time", "domain" => [hd(days), List.last(days)]}},
        "layers" => [
          %{
            "columns" => %{"x" => days, "color" => categories},
            "tooltip" => [
              %{"title" => "Day", "values" => days},
              %{"title" => "Name", "values" => Enum.map(days, &"d#{&1}")}
            ]
          }
        ],
        "facet" => %{
          "panels" => [
            %{"title" => "A", "layers" => [%{"columns" => %{"x" => days}, "tooltip" => []}]}
          ]
        }
      }

      packed = Wire.pack(wire)
      assert is_map(get_in(packed, ["layers", Access.at(0), "columns", "x"]))
      assert get_in(packed, ["layers", Access.at(0), "columns", "color"]) == categories
      assert is_map(get_in(packed, ["layers", Access.at(0), "tooltip", Access.at(0), "values"]))
      assert is_list(get_in(packed, ["layers", Access.at(0), "tooltip", Access.at(1), "values"]))

      assert is_map(
               get_in(packed, [
                 "facet",
                 "panels",
                 Access.at(0),
                 "layers",
                 Access.at(0),
                 "columns",
                 "x"
               ])
             )

      assert packed["scales"] == wire["scales"]

      assert packed |> sent() |> Wire.unpack() == sent(wire)
    end

    test "a wire without layers is as it is" do
      for wire <- [%{"kind" => "number", "single" => %{"value" => 3}}, %{"layers" => []}] do
        assert Wire.pack(wire) == wire
        assert Wire.unpack(wire) == wire
      end
    end

    property "every chart comes back the same, and its table too" do
      check all(rows <- rows(), build <- member_of(charts()), max_runs: 150) do
        case Fude.Compile.compile(build.(rows)) do
          {:ok, wire} ->
            plain = sent(wire)
            back = wire |> Wire.pack() |> sent() |> Wire.unpack()
            assert back == plain
            assert Fude.Compile.table(back) == Fude.Compile.table(plain)

          {:error, _} ->
            :ok
        end
      end
    end
  end

  # Rows as an app has them: days in order (one for each series, some
  # skipped), numbers of a few decimals, now and then a missing value.
  defp rows do
    gen all(
          n <- integer(1..300),
          series <- integer(1..4),
          decimals <- integer(0..3),
          gaps <- list_of(boolean(), length: n),
          values <- list_of(one_of([integer(-1_000..100_000), constant(nil)]), length: n * series)
        ) do
      days =
        for {gap, i} <- Enum.with_index(gaps),
            not gap or rem(i, 5) != 0,
            do: Date.add(~D[2024-01-01], i)

      for {day, d} <- Enum.with_index(days), s <- 1..series do
        value = Enum.at(values, d * series + s - 1)

        %{
          day: day,
          at: DateTime.new!(day, Time.new!(rem(d, 24), 0, 0)),
          series: "S#{s}",
          value: value && Float.round(value / Integer.pow(10, decimals), decimals),
          count: value && abs(value),
          n: d * 1.5
        }
      end
    end
  end

  defp charts do
    [
      &Fude.line(&1, x: :day, y: :value, color: :series),
      &Fude.line(&1, x: {:month, :day}, y: {:mean, :value}, color: :series),
      &Fude.line(&1, x: :at, y: :count),
      &Fude.area(&1, x: :day, y: :count, color: :series),
      &Fude.bar(&1, x: :series, y: {:sum, :value}),
      &Fude.bar(&1, x: {:week, :day}, y: {:sum, :count}, color: :series),
      &Fude.scatter(&1, x: :n, y: :value, color: :series),
      &Fude.histogram(&1, x: :value),
      &Fude.heatmap(&1, x: {:month, :day}, y: :series, color: {:sum, :count})
    ]
  end

  describe "the shared fixture" do
    test "is up to date" do
      if System.get_env("FUDE_WRITE_FIXTURES") == "1" do
        File.write!(@fixture_path, JSON.encode!(%{"columns" => fixture_cases()}) <> "\n")
      end

      assert @fixture["columns"] == sent(fixture_cases()),
             "test/fixtures/wire.json is out of date: run FUDE_WRITE_FIXTURES=1 mix test #{__ENV__.file}"
    end

    test "each packed column unpacks to its values" do
      for %{"name" => name, "values" => values, "packed" => packed} <- @fixture["columns"] do
        assert Wire.pack_column(values) == packed, name
        assert_same(Wire.unpack_column(packed), values)
      end
    end
  end

  # The cases of the fixture: each column's values and what pack_column/1
  # makes of them (a list when it stays as it is). Made from a seed, the
  # same on every run.
  def fixture_cases do
    :rand.seed(:exsss, {20, 26, 10})

    for {name, values} <- hand_cases() ++ seeded_cases(),
        do: %{"name" => name, "values" => values, "packed" => Wire.pack_column(values)}
  end

  defp days(n, from), do: for(i <- 0..(n - 1), do: from + i * @day)

  defp every(values, n, value),
    do:
      values
      |> Enum.with_index()
      |> Enum.map(fn {v, i} -> if rem(i, n) == 0, do: value, else: v end)

  defp hand_cases do
    [
      {"days", days(120, 1_672_531_200_000)},
      {"days for each of four series",
       Enum.flat_map(days(100, 1_672_531_200_000), &List.duplicate(&1, 4))},
      {"days with nil", every(days(150, 1_600_000_000_000), 9, nil)},
      {"nil first and last", [nil, nil | days(100, 0)] ++ [nil]},
      {"hours before 1970", series(&(-86_400_000_000 + &1 * 3_600_000))},
      {"falling", series(&(9_000_000_000 - &1 * 37_000))},
      {"one value", List.duplicate(123_456_789_000, 150)},
      {"quarters of a unit", series(&(2.5 + &1 * 0.25))},
      {"whole floats", series(&(50_000.0 + &1 * 2))},
      {"negative floats", series(&(-12.5 + &1 * 0.125))},
      {"near 2^52", series(&(@max_int - 200_000 + &1 * 1_000))},
      {"from 2^52", series(&(@max_int + &1))},
      {"short", [1, 2, 3]},
      {"words", series(&"w#{&1}")},
      {"ints and floats", every(series(&(&1 * 1_000_000.0)), 2, 7_000_000)},
      {"seven decimals", series(&(1.0 + &1 * 1.0e-7))},
      {"no short decimals", series(&:math.sqrt(&1 + 2))}
    ]
  end

  defp series(fun), do: Enum.map(0..149, fun)

  defp seeded_cases do
    for d <- 0..6, order <- [:sorted, :random] do
      values = for _ <- 1..200, do: Float.round((:rand.uniform() - 0.3) * 10_000, d)

      {"#{order} floats of #{d} decimals",
       if(order == :sorted, do: Enum.sort(values), else: values)}
    end
  end
end
