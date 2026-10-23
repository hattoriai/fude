defmodule Fude.RulesTest do
  use ExUnit.Case, async: true

  alias Fude.Rules

  # The cases that the browser's rules.ts runs too.
  @fixture "test/fixtures/rules.json" |> File.read!() |> JSON.decode!()

  describe "the shared fixture" do
    test "increment" do
      for %{"args" => [a, b, c], "expected" => expected} <- @fixture["increment"] do
        assert Rules.increment(a, b, c) == expected, "increment(#{a}, #{b}, #{c})"
      end
    end

    test "ticks" do
      for %{"args" => [a, b, c], "expected" => expected} <- @fixture["ticks"] do
        assert Rules.ticks(a, b, c) == expected, "ticks(#{a}, #{b}, #{c})"
      end
    end

    test "nice" do
      for %{"args" => [a, b, c], "expected" => expected} <- @fixture["nice"] do
        assert Tuple.to_list(Rules.nice(a, b, c)) == expected, "nice(#{a}, #{b}, #{c})"
      end
    end

    test "bins" do
      for %{"args" => [a, b, c], "expected" => expected} <- @fixture["bins"] do
        assert Tuple.to_list(Rules.bins(a, b, c)) == expected, "bins(#{a}, #{b}, #{c})"
      end
    end

    test "floor and offset" do
      for %{"args" => [time, unit], "expected" => expected} <- @fixture["floor"] do
        assert Rules.floor(time, String.to_existing_atom(unit)) == expected
      end

      for %{"args" => [time, unit, step], "expected" => expected} <- @fixture["offset"] do
        assert Rules.offset(time, String.to_existing_atom(unit), step) == expected
      end
    end

    test "time ticks" do
      for %{"args" => [a, b, c], "expected" => expected} <- @fixture["timeTicks"] do
        {unit, step, ticks} = Rules.time_ticks(a, b, c)
        assert %{"unit" => Atom.to_string(unit), "step" => step, "ticks" => ticks} == expected
      end
    end
  end

  test "the days of the calendar go there and back" do
    for days <- [-800_000, -1, 0, 1, 59, 10_957, 20_454, 2_932_896] do
      {y, m, d} = Rules.civil(days * 86_400_000)
      assert Rules.days(y, m, d) == days
      assert Date.add(~D[1970-01-01], days) == Date.new!(y, m, d)
    end
  end

  test "a week starts on Monday" do
    # 2026-10-22 is a Thursday.
    time = DateTime.to_unix(~U[2026-10-22 15:00:00Z], :millisecond)
    assert Rules.floor(time, :week) == DateTime.to_unix(~U[2026-10-19 00:00:00Z], :millisecond)
  end

  test "the last bin holds the largest value" do
    bins = Rules.bins(0, 100, 10)
    assert Rules.bin(bins, 100) == 9
    assert Rules.bin(bins, 0) == 0
    assert Rules.bin(bins, 9.99) == 0
  end
end
