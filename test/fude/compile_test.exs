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
end
