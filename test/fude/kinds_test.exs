defmodule Fude.KindsTest do
  # The timeline, box plot, candlestick, treemap, radar and radial bars:
  # what the server works out for each, as the browser and the table get it.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Fude.Compile

  defp compile!(chart) do
    {:ok, wire} = Compile.compile(chart)
    wire
  end

  defp layer(wire, i \\ 0), do: Enum.at(wire["layers"], i)
  defp column(wire, name, i \\ 0), do: layer(wire, i)["columns"][name]

  @day 86_400_000

  describe "timeline" do
    @tasks [
      %{task: "Design", start: ~D[2026-03-02], finish: ~D[2026-03-09], team: "UX"},
      %{task: "Build", start: ~D[2026-03-20], finish: ~D[2026-03-06], team: "Eng"},
      %{task: "Ship", start: ~D[2026-03-25], finish: nil, team: "Eng"}
    ]

    test "a floating bar for each task, from the earlier date to the later" do
      wire = compile!(Fude.timeline(@tasks, y: :task, x: :start, x2: :finish, color: :team))
      march = &(Date.diff(&1, ~D[1970-01-01]) * @day)

      assert %{"mark" => "bar", "horizontal" => true, "stack" => "range"} = layer(wire)
      # A row with no end is left out; an end before its start is the start.
      assert column(wire, "x0") == [march.(~D[2026-03-02]), march.(~D[2026-03-06])]
      assert column(wire, "x1") == [march.(~D[2026-03-09]), march.(~D[2026-03-20])]
      assert wire["scales"]["y"]["domain"] == ["Design", "Build"]
      assert %{"type" => "time", "unit" => "day"} = wire["scales"]["x"]
      assert wire["scales"]["x"]["domain"] == [march.(~D[2026-03-02]), march.(~D[2026-03-20])]
      assert layer(wire)["options"]["labels"] == false
    end

    test "its table: the task, its start, its end and its color" do
      wire = compile!(Fude.timeline(@tasks, y: :task, x: :start, x2: :finish, color: :team))

      assert Compile.table(wire) ==
               {["Task", "Start", "Finish", "Team"],
                [
                  ["Design", ~D[2026-03-02], ~D[2026-03-09], "UX"],
                  ["Build", ~D[2026-03-06], ~D[2026-03-20], "Eng"]
                ]}
    end

    test "numbers on the axis: a range of anything that counts" do
      rows = [%{lap: "1", from: 0, to: 61.2}, %{lap: "2", from: 61.2, to: 120.9}]
      wire = compile!(Fude.timeline(rows, y: :lap, x: :from, x2: :to))
      assert %{"type" => "linear"} = wire["scales"]["x"]
      assert column(wire, "x1") == [61.2, 120.9]
    end

    test "needs a start and an end" do
      assert_raise ArgumentError, ~r/a timeline chart needs :x2/, fn ->
        Fude.timeline(y: :task, x: :start)
      end
    end
  end

  describe "box plot" do
    test "the quartiles, median and whiskers of each category, as R and NumPy have them" do
      rows = for v <- 1..10, do: %{g: "A", v: v}
      wire = compile!(Fude.boxplot(rows, x: :g, y: :v))

      assert %{"mark" => "box"} = layer(wire)
      assert column(wire, "b0") == [3.25]
      assert column(wire, "mid") == [5.5]
      assert column(wire, "b1") == [7.75]
      assert column(wire, "lo") == [1]
      assert column(wire, "hi") == [10]
      assert column(wire, "n") == [10]
      assert length(wire["layers"]) == 1
    end

    test "the values beyond 1.5 boxes from it are outliers, a layer of points" do
      rows = for v <- [1, 2, 3, 4, 5, 6, 7, 8, 9, 40], do: %{g: "A", v: v}
      wire = compile!(Fude.boxplot(rows, x: :g, y: :v))

      # The whisker ends at the last value within the fence, not at the fence.
      assert column(wire, "hi") == [9]
      assert %{"mark" => "point", "options" => %{"outliers" => true}} = layer(wire, 1)
      assert column(wire, "y", 1) == [40]
      assert wire["scales"]["y"]["domain"] |> List.last() >= 40

      wire = compile!(Fude.boxplot(rows, x: :g, y: :v, outliers: false))
      assert length(wire["layers"]) == 1
    end

    test "a whisker never ends inside its box" do
      # Q3 is interpolated to 250,000: 1,000,000 is beyond its fence, and no
      # other value is above Q3, so the whisker ends at Q3, not back at 0.
      rows = for v <- [1_000_000, 0, 0, 0], do: %{g: "A", v: v}
      wire = compile!(Fude.boxplot(rows, x: :g, y: :v))
      assert column(wire, "b1") == [250_000.0]
      assert column(wire, "hi") == [250_000.0]
      assert column(wire, "y", 1) == [1_000_000]
    end

    test "categories in their order, a box of one value, no box with no number" do
      rows = [%{g: "B", v: 4}, %{g: "A", v: 1}, %{g: "A", v: 3}, %{g: "C", v: nil}]
      wire = compile!(Fude.boxplot(rows, x: :g, y: :v))

      assert wire["scales"]["x"]["domain"] == ["B", "A"]
      assert column(wire, "mid") == [4, 2.0]
      assert column(wire, "lo") == [4, 1]
    end

    test "its table: each category's five numbers and count" do
      rows = for v <- 1..5, do: %{region: "North", days: v}
      wire = compile!(Fude.boxplot(rows, x: :region, y: :days))

      assert Compile.table(wire) ==
               {["Region", "Low", "Q1", "Median", "Q3", "High", "Count"],
                [["North", 1, 2.0, 3.0, 4.0, 5, 5]]}
    end

    property "every box is in order, and its outliers outside its whiskers" do
      check all(
              values <-
                list_of(one_of([integer(-1000..1000), float(min: -1.0e6, max: 1.0e6)]),
                  min_length: 1,
                  max_length: 200
                )
            ) do
        wire = compile!(Fude.boxplot(Enum.map(values, &%{g: "A", v: &1}), x: :g, y: :v))
        [lo, b0, mid, b1, hi] = Enum.map(~w(lo b0 mid b1 hi), &hd(column(wire, &1)))
        sorted = Enum.sort(values)

        assert lo <= b0 and b0 <= mid and mid <= b1 and b1 <= hi

        # A whisker ends at a value, or at its quartile when no value within its fence is beyond it.
        assert lo in values or lo == b0
        assert hi in values or hi == b1
        assert hd(column(wire, "n")) == length(values)
        assert_in_delta mid, median(sorted), 1.0e-6 * max(1, abs(mid))

        outliers = if length(wire["layers"]) == 2, do: column(wire, "y", 1), else: []
        assert length(outliers) + Enum.count(values, &(&1 >= lo and &1 <= hi)) == length(values)
        reach = 1.5 * (b1 - b0)
        assert Enum.all?(outliers, &(&1 < b0 - reach or &1 > b1 + reach))
      end
    end
  end

  defp median(sorted) do
    n = length(sorted)

    if rem(n, 2) == 1,
      do: Enum.at(sorted, div(n, 2)),
      else: (Enum.at(sorted, div(n, 2) - 1) + Enum.at(sorted, div(n, 2))) / 2
  end

  describe "candlestick" do
    @prices [
      %{day: ~D[2026-03-03], o: 11, h: 13, l: 9, c: 10},
      %{day: ~D[2026-03-02], o: 10, h: 12, l: 9, c: 11},
      %{day: ~D[2026-03-04], o: 10, h: nil, l: 9, c: 11}
    ]

    test "a candle for each day, in time order, up or down by its close" do
      wire = compile!(Fude.candlestick(@prices, x: :day, open: :o, high: :h, low: :l, close: :c))

      assert %{"mark" => "box"} = layer(wire)
      # A day with a price missing is left out.
      assert length(column(wire, "x")) == 2
      assert column(wire, "b0") == [10, 11]
      assert column(wire, "b1") == [11, 10]
      assert column(wire, "lo") == [9, 9]
      assert column(wire, "hi") == [12, 13]
      refute Map.has_key?(layer(wire)["columns"], "mid")

      assert %{
               "domain" => ["Increase", "Decrease"],
               "roles" => ["increase", "decrease"],
               "legend" => false
             } =
               wire["scales"]["color"]

      assert column(wire, "color") == [0, 1]
    end

    test "its table: the day and its four prices, by their titles" do
      wire =
        compile!(
          Fude.candlestick(@prices,
            x: :day,
            open: :o,
            high: :h,
            low: [field: :l, title: "Lowest"],
            close: :c
          )
        )

      assert {["Day", "O", "H", "Lowest", "C"], [[~D[2026-03-02], 10, 12, 9, 11] | _]} =
               Compile.table(wire)
    end
  end

  describe "treemap" do
    test "a tile for each name, largest first, summed; none for nothing" do
      rows = [
        %{c: "A", p: 5},
        %{c: "B", p: 9},
        %{c: "A", p: 2},
        %{c: "Z", p: 0},
        %{c: "N", p: -3}
      ]

      wire = compile!(Fude.treemap(rows, name: :c, value: :p))

      assert %{"mark" => "tile"} = layer(wire)
      assert wire["scales"]["name"]["domain"] == ["B", "A"]
      assert column(wire, "value") == [9, 7]
      assert wire["axes"] == false
      assert Compile.table(wire) == {["C", "P"], [["B", 9], ["A", 7]]}
    end

    test "a color keeps its tiles together and has a legend" do
      wire =
        compile!(
          Fude.treemap([%{c: "A", p: 5, s: "x"}, %{c: "B", p: 9, s: "y"}],
            name: :c,
            value: :p,
            color: :s
          )
        )

      assert %{"type" => "ordinal", "domain" => ["y", "x"]} = wire["scales"]["color"]
      assert {["C", "P", "S"], [["B", 9, "y"], ["A", 5, "x"]]} = Compile.table(wire)
    end
  end

  describe "radar" do
    test "a spoke for each category, from zero; the values of a spoke and series summed" do
      rows = [
        %{m: "Speed", s: 80, t: "A"},
        %{m: "Size", s: 30, t: "A"},
        %{m: "Size", s: 20, t: "A"},
        %{m: "Speed", s: 20, t: "B"}
      ]

      wire = compile!(Fude.radar(rows, x: :m, y: :s, color: :t))

      assert %{"mark" => "radar"} = layer(wire)
      assert wire["scales"]["x"]["domain"] == ["Speed", "Size"]
      assert [0, 80] = wire["scales"]["y"]["domain"]
      assert column(wire, "y") == [80, 50, 20]
      assert wire["axes"] == false
      assert wire["description"] =~ "A radar chart"
    end
  end

  describe "radial bars" do
    test "each ring's arc its share of 100, or of the max given" do
      rows = [%{c: "A", v: 50}, %{c: "B", v: 25}, %{c: "C", v: -5}]
      assert column(compile!(Fude.radial_bar(rows, x: :c, y: :v)), "a1") == [0.5, 0.25, +0.0]

      assert column(compile!(Fude.radial_bar(rows, x: :c, y: :v, max: 50)), "a1") == [
               1.0,
               0.5,
               +0.0
             ]
    end

    test "of the largest value when it is over 100 and no max is given; a value over the max is a whole ring" do
      rows = [%{c: "A", v: 400}, %{c: "B", v: 100}]
      wire = compile!(Fude.radial_bar(rows, x: :c, y: :v))
      assert column(wire, "a1") == [1.0, 0.25]
      assert wire["scales"]["y"]["domain"] == [0, 400]
      assert column(compile!(Fude.radial_bar(rows, x: :c, y: :v, max: 200)), "a1") == [1, 0.5]
    end
  end

  describe "specs" do
    test "each kind loads as it was dumped" do
      for chart <- [
            Fude.timeline(y: :task, x: :start, x2: :finish, color: :team),
            Fude.boxplot(x: :region, y: :days, outliers: false),
            Fude.candlestick(
              x: :day,
              open: :o,
              high: :h,
              low: :l,
              close: [field: :c, format: {:currency, "EUR"}]
            ),
            Fude.treemap(name: :city, value: :people, color: :country, labels: false),
            Fude.radar(x: :measure, y: :score, color: :product),
            Fude.radial_bar(x: :channel, y: :done, max: 120)
          ] do
        assert {:ok, chart} ==
                 chart |> Fude.Spec.dump() |> JSON.encode!() |> JSON.decode!() |> Fude.Spec.load()
      end
    end
  end
end
