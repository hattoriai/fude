defmodule Fude.CompileTest do
  use ExUnit.Case, async: true

  alias Fude.Compile

  @sales [
    %{region: "North", channel: "Online", revenue: 120},
    %{region: "North", channel: "Retail", revenue: 80},
    %{region: "South", channel: "Online", revenue: 60},
    %{region: "South", channel: "Retail", revenue: 90},
    %{region: "North", channel: "Online", revenue: 30}
  ]

  defp compile!(chart) do
    {:ok, wire} = Compile.compile(chart)
    wire
  end

  test "every kind compiles to JSON" do
    days =
      for d <- 0..20,
          do: %{day: Date.add(~D[2026-01-01], d), n: d * 3, k: rem(d, 3), s: "s#{rem(d, 2)}"}

    charts = [
      Fude.bar(@sales, x: :region, y: :revenue, color: :channel),
      Fude.bar(@sales, x: :region, y: :revenue, horizontal: true, labels: true),
      Fude.line(days, x: :day, y: :n, color: :s),
      Fude.area(days, x: :day, y: :n, color: :s),
      Fude.scatter(days, x: :n, y: :k, color: :s),
      Fude.bubble(days, x: :n, y: :k, size: :n),
      Fude.pie(@sales, value: :revenue, color: :channel),
      Fude.donut(@sales, value: :revenue, color: :channel, inner: 0.5),
      Fude.histogram(days, x: :n, bins: 5),
      Fude.heatmap(@sales, x: :region, y: :channel, color: :revenue),
      Fude.sparkline(days, x: :day, y: :n),
      Fude.number(days, value: {:sum, :n}, label: "Total"),
      Fude.trend(days, value: :n),
      Fude.progress(days, value: :n, goal: 50),
      Fude.layers(days, [Fude.line(x: :day, y: :n), Fude.rule(y: 30, label: "Goal")])
    ]

    for chart <- charts do
      wire = compile!(chart)
      assert wire |> JSON.encode!() |> JSON.decode!() == wire
    end
  end

  describe "digits" do
    test "go on the wire after the format" do
      wire = compile!(Fude.number([%{n: 1.5}], value: [field: :n, format: :number, digits: 0]))
      assert wire["single"]["format"] == "number:0"

      wire =
        compile!(
          Fude.bar([%{r: "N", v: 1}],
            x: :r,
            y: [field: :v, format: {:currency, "EUR"}, digits: 2]
          )
        )

      assert wire["scales"]["y"]["format"] == "currency:EUR:2"

      assert compile!(Fude.number([%{n: 1}], value: [field: :n, digits: 1]))["single"]["format"] ==
               ":1"

      assert compile!(Fude.number([%{n: 1}], value: :n))["single"]["format"] == nil
    end

    test "are a whole number from 0 to 20" do
      assert_raise ArgumentError, ~r/:digits of :value must be a whole number from 0 to 20/, fn ->
        Fude.number([%{n: 1}], value: [field: :n, digits: 21])
      end
    end
  end

  describe "the right axis" do
    @days for d <- 0..4,
              do: %{day: Date.add(~D[2026-01-01], d), orders: d + 1, revenue: (d + 1) * 1000}

    test "a layer of y on the right has a y scale of its own" do
      wire =
        compile!(
          Fude.layers(@days, [
            Fude.bar(x: :day, y: :orders),
            Fude.line(x: :day, y: [field: :revenue, axis: :right])
          ])
        )

      assert %{"y" => %{"domain" => [0, 5]}, "yRight" => %{"domain" => [1000, 5000]}} =
               wire["scales"]

      assert %{"y" => %{"title" => "Orders"}, "yRight" => %{"title" => "Revenue"}} =
               wire["scales"]

      assert [%{"axis" => nil}, %{"axis" => "right", "columns" => %{"y" => ys}}] =
               wire["layers"]

      assert ys == [1000, 2000, 3000, 4000, 5000]
    end

    test "layers on the left share their scale; on the right, theirs" do
      wire =
        compile!(
          Fude.layers(@days, [
            Fude.bar(x: :day, y: :orders),
            Fude.rule(y: 10),
            Fude.line(x: :day, y: [field: :revenue, axis: :right])
          ])
        )

      assert wire["scales"]["y"]["domain"] == [0, 10]
      assert wire["scales"]["yRight"]["domain"] == [1000, 5000]
    end

    test "a chart with no layer on the right has no right scale" do
      wire = compile!(Fude.line(@days, x: :day, y: [field: :revenue, axis: :left]))
      refute Map.has_key?(wire["scales"], "yRight")
    end
  end

  describe "stacks in the order of the series, whatever the order of the rows" do
    # The rows of each month in another order of the channels, as a query
    # ordered by month only gives them.
    @shuffled [
      %{month: ~D[2026-01-01], channel: "Online", revenue: 10},
      %{month: ~D[2026-01-01], channel: "Retail", revenue: 20},
      %{month: ~D[2026-02-01], channel: "Retail", revenue: 25},
      %{month: ~D[2026-02-01], channel: "Online", revenue: 15},
      %{month: ~D[2026-03-01], channel: "Online", revenue: 12},
      %{month: ~D[2026-03-01], channel: "Retail", revenue: 22}
    ]

    # Each series' base and top, month by month.
    defp bands(%{"layers" => [layer], "scales" => %{"color" => %{"domain" => domain}}}) do
      %{"color" => colors, "y0" => y0, "y1" => y1} = layer["columns"]

      [colors, y0, y1]
      |> Enum.zip()
      |> Enum.group_by(fn {c, _, _} -> Enum.at(domain, c) end, fn {_, b, t} -> {b, t} end)
    end

    test "an area: the first series at the bottom of every month" do
      bands = bands(compile!(Fude.area(@shuffled, x: :month, y: :revenue, color: :channel)))
      assert bands["Online"] == [{0, 10}, {0, 15}, {0, 12}]
      assert bands["Retail"] == [{10, 30}, {15, 40}, {12, 34}]
    end

    test "bars: the same" do
      bands = bands(compile!(Fude.bar(@shuffled, x: :month, y: :revenue, color: :channel)))
      assert bands["Online"] == [{0, 10}, {0, 15}, {0, 12}]
      assert bands["Retail"] == [{10, 30}, {15, 40}, {12, 34}]
    end

    test "a sorted color stacks in its sort" do
      chart =
        Fude.area(@shuffled, x: :month, y: :revenue, color: [field: :channel, sort: :descending])

      bands = bands(compile!(chart))
      assert bands["Retail"] == [{0, 20}, {0, 25}, {0, 22}]
    end
  end

  test "a bar sums the rows of its category and color" do
    wire = compile!(Fude.bar(@sales, x: :region, y: :revenue, color: :channel))
    {_heads, rows} = Compile.table(wire)
    assert ["North", 150, "Online"] in rows
  end

  test "bars of a color stack: each has its base and its top" do
    %{"layers" => [layer]} = compile!(Fude.bar(@sales, x: :region, y: :revenue, color: :channel))
    assert layer["stack"] == "zero"
    assert layer["columns"]["y0"] == [0, 150, 0, 60]
    assert layer["columns"]["y1"] == [150, 230, 60, 150]
  end

  test "sorts the categories by their totals" do
    wire = compile!(Fude.bar(@sales, x: [field: :region, sort: :"-y"], y: :revenue))
    assert wire["scales"]["x"]["domain"] == ["North", "South"]
    wire = compile!(Fude.bar(@sales, x: [field: :region, sort: :y], y: :revenue))
    assert wire["scales"]["x"]["domain"] == ["South", "North"]
  end

  test "a histogram counts the values in round bins" do
    data = for v <- [1, 2, 2, 3, 9, 10], do: %{v: v}

    %{"layers" => [layer], "scales" => %{"x" => x}} =
      compile!(Fude.histogram(data, x: :v, bins: 5))

    assert x["bins"] == %{"start" => 0.0, "step" => 2.0}
    assert Enum.sum(layer["columns"]["y"]) == 6
    assert List.last(layer["columns"]["x2"]) == 10.0
  end

  test "takes a time's unit" do
    data = [
      %{at: ~U[2026-03-15 10:00:00Z], n: 1},
      %{at: ~U[2026-03-20 10:00:00Z], n: 2},
      %{at: ~U[2026-04-02 10:00:00Z], n: 3}
    ]

    wire = compile!(Fude.bar(data, x: {:month, :at}, y: :n))
    assert {_heads, [[~D[2026-03-01], 3], [~D[2026-04-01], 3]]} = Compile.table(wire)
  end

  test "dates at the first of each month are months" do
    data = [%{m: ~D[2026-01-01], n: 1}, %{m: ~D[2026-02-01], n: 2}]

    assert %{"scales" => %{"x" => %{"type" => "time", "unit" => "month"}}} =
             compile!(Fude.line(data, x: :m, y: :n))
  end

  test "a field that is not in the data is an error with a suggestion" do
    assert {:error, [message]} = Compile.compile(Fude.bar(@sales, x: :regoin, y: :revenue))
    assert message == ~s|x: the field "regoin" is not in the data; did you mean "region"?|
  end

  test "takes the rows of a query result" do
    result = %{
      columns: ["region", "revenue"],
      rows: [["North", Decimal.new("10.5")], ["South", Decimal.new("2")]]
    }

    wire = compile!(Fude.bar(result, x: :region, y: :revenue))
    assert {_heads, [["North", 10.5], ["South", 2.0]]} = Compile.table(wire)
  end

  test "writes a description for screen readers" do
    wire = compile!(Fude.bar(@sales, x: :region, y: :revenue, color: :channel, title: "Revenue"))

    assert wire["description"] ==
             "Revenue. A bar chart. x axis, Region: 2 categories. y axis, Revenue: from 0 to 230. 2 series by Channel: Online, Retail."
  end

  describe "maps" do
    test "a choropleth sums the value of each region and names its map" do
      data = [%{c: "PRT", n: 2}, %{c: "PRT", n: 3}, %{c: "ESP", n: 4}]
      wire = compile!(Fude.choropleth(data, region: :c, color: :n))

      assert %{"layers" => [%{"mark" => "region", "options" => %{"map" => "world"}} = layer]} =
               wire

      assert wire["scales"]["region"]["domain"] == ["PRT", "ESP"]
      assert layer["columns"]["color"] == [5, 4]
      assert wire["axes"] == false
      assert wire["description"] =~ "2 regions by C"
    end

    test "a bubble map sizes its circles from zero" do
      data = [%{s: "CA", n: 20}, %{s: "TX", n: 5}]
      wire = compile!(Fude.bubble_map(data, region: :s, size: :n, map: "us-states"))
      assert %{"layers" => [%{"mark" => "bubble", "options" => %{"map" => "us-states"}}]} = wire
      assert wire["scales"]["size"]["domain"] == [0, 20]
    end

    test "a map's spec goes there and back" do
      chart = Fude.choropleth(region: :country, color: {:sum, :users}, map: "us-states")
      assert {:ok, ^chart} = chart |> Fude.Spec.dump() |> Fude.Spec.load()
    end
  end

  describe "waterfalls, funnels and gauges" do
    test "a waterfall carries a running total, with a start and an end that stand on zero" do
      data = [%{s: "Start", v: 100}, %{s: "Sales", v: 40}, %{s: "Costs", v: -50}]
      wire = compile!(Fude.waterfall(data, x: :s, y: :v, start: "Start", total: "End"))
      %{"layers" => [%{"columns" => columns, "stack" => "waterfall"}]} = wire

      assert columns["y0"] == [0, 100, 140, 0]
      assert columns["y1"] == [100, 140, 90, 90]
      assert wire["scales"]["x"]["domain"] == ["Start", "Sales", "Costs", "End"]
      assert wire["scales"]["color"]["roles"] == ["increase", "decrease", "total"]
    end

    test "a funnel gives each stage its share of the first" do
      data = [%{s: "Visit", n: 1000}, %{s: "Buy", n: 90}]
      %{"layers" => [layer]} = compile!(Fude.funnel(data, x: :s, y: :n))
      assert layer["columns"]["share"] == [1.0, 0.09]
      assert layer["horizontal"]
      assert layer["columns"]["x0"] == [-500.0, -45.0]
    end

    test "a gauge is a single value with its range and target" do
      wire = compile!(Fude.gauge([%{p: 72}], value: :p, min: 50, max: 90, target: 80))
      assert %{"value" => 72, "min" => 50, "max" => 90, "target" => 80} = wire["single"]
    end

    test "a single value is centered unless it says start" do
      assert get_in(compile!(Fude.number([%{n: 1}], value: :n)), ["single", "align"]) == "center"

      assert get_in(compile!(Fude.progress([%{n: 1}], value: :n, align: :start)), [
               "single",
               "align"
             ]) ==
               "start"

      assert_raise ArgumentError,
                   ~r/:align of a number chart must be one of :center, :start/,
                   fn ->
                     Fude.number([%{n: 1}], value: :n, align: :left)
                   end
    end
  end

  describe "annotations" do
    test "go on the chart's scales: a category by its index, a date in milliseconds" do
      days = for d <- 0..9, do: %{day: Date.add(~D[2026-01-01], d), n: d}

      wire =
        days
        |> Fude.line(x: :day, y: :n)
        |> Fude.annotate(:band, x: {~D[2026-01-02], ~D[2026-01-04]}, text: "Launch")
        |> Fude.annotate(:label, x: ~D[2026-01-05], y: 4, text: "Peak")
        |> compile!()

      assert [%{"type" => "band", "x" => x0, "x2" => x1}, %{"type" => "label", "y" => 4}] =
               wire["annotations"]

      assert x0 == DateTime.to_unix(~U[2026-01-02 00:00:00Z], :millisecond)
      assert x1 == DateTime.to_unix(~U[2026-01-04 00:00:00Z], :millisecond)

      wire =
        @sales
        |> Fude.bar(x: :region, y: :revenue)
        |> Fude.annotate(:label, x: "South", text: "!")
        |> compile!()

      assert [%{"x" => 1}] = wire["annotations"]
    end

    test "go into the spec and back, a date as its text" do
      chart =
        Fude.line(x: :day, y: :n)
        |> Fude.annotate(:band, x: {~D[2026-01-02], ~D[2026-01-04]}, text: "Launch")
        |> Fude.annotate(:line, y: 10)

      spec = Fude.Spec.dump(chart)

      assert [
               %{"type" => "band", "x" => %{"from" => "2026-01-02", "to" => "2026-01-04"}},
               %{"type" => "line", "y" => 10}
             ] = spec["annotations"]

      assert {:ok, ^chart} = spec |> JSON.encode!() |> JSON.decode!() |> Fude.Spec.load()
    end

    test "say what is missing" do
      assert_raise ArgumentError, ~r/a band needs an x or a y of {from, to}/, fn ->
        Fude.annotate(Fude.line(x: :day, y: :n), :band, x: 3)
      end
    end
  end

  describe "small multiples" do
    @by_region [
      %{region: "North", month: ~D[2026-01-01], n: 10, c: "A"},
      %{region: "North", month: ~D[2026-02-01], n: 30, c: "A"},
      %{region: "South", month: ~D[2026-01-01], n: 5, c: "B"},
      %{region: "South", month: ~D[2026-02-01], n: 7, c: "A"}
    ]

    test "a panel for each value, on scales they share" do
      wire =
        compile!(
          @by_region
          |> Fude.bar(x: :month, y: :n, color: :c)
          |> Fude.facet(:region, columns: 2)
        )

      %{"facet" => %{"title" => "Region", "columns" => 2, "panels" => [north, south]}} = wire

      assert north["title"] == "North"
      assert south["title"] == "South"
      # The largest bar of any panel, not of all the panels summed.
      assert wire["scales"]["y"]["domain"] == [0, 30]
      assert wire["scales"]["color"]["domain"] == ["A", "B"]
      # Each panel's colors are the shared scale's: South's "A" is 0.
      assert south["layers"] |> hd() |> get_in(["columns", "color"]) == [1, 0]
    end

    test "the table has the facet's field" do
      wire = compile!(@by_region |> Fude.bar(x: :month, y: :n) |> Fude.facet(:region))
      assert {["Region", "Month", "N"], [["North", ~D[2026-01-01], 10] | _]} = Compile.table(wire)
    end

    test "goes into the spec and back" do
      chart = Fude.line(x: :month, y: :n) |> Fude.facet(:region, columns: 3)
      assert %{"facet" => %{"field" => "region", "columns" => 3}} = Fude.Spec.dump(chart)
      assert {:ok, ^chart} = chart |> Fude.Spec.dump() |> Fude.Spec.load()
    end

    test "a facet's field that is not in the data is an error" do
      assert {:error, [message]} =
               Compile.compile(@by_region |> Fude.bar(x: :month, y: :n) |> Fude.facet(:regoin))

      assert message =~ ~s|facet: the field "regoin" is not in the data; did you mean "region"?|
    end
  end
end
