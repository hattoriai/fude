defmodule Fude.ElectionTest do
  # What an election night needs: a parliament, bars colored by their own
  # parties, columns of changes, segments named by their series, a majority
  # on one bar, and a map shaded by a lead.
  use ExUnit.Case, async: true

  alias Fude.Compile

  @results [
    %{party: "Social", seats: 83, votes: 29.4, change: 25},
    %{party: "Forward!", seats: 73, votes: 27.9, change: 13},
    %{party: "Alliance", seats: 55, votes: 21.6, change: -36},
    %{party: "Left", seats: 0, votes: 1.8, change: 0}
  ]

  defp compile!(chart) do
    {:ok, wire} = Compile.compile(chart)
    wire
  end

  defp layer(wire, i \\ 0), do: Enum.at(wire["layers"], i)

  describe "parliament" do
    test "each party's seats, a whole number, in the parties' order; none for none" do
      rows = [%{p: "A", s: 83}, %{p: "B", s: 73.4}, %{p: "C", s: 0}, %{p: "D", s: 74}]
      wire = compile!(Fude.parliament(rows, color: :p, value: :s, majority: 116))

      assert %{"mark" => "seats", "options" => %{"majority" => 116, "total" => 230}} = layer(wire)
      assert layer(wire)["columns"]["value"] == [83, 73, 74]
      assert wire["scales"]["color"]["domain"] == ["A", "B", "D"]
      assert wire["axes"] == false
    end

    test "says its seats, its majority and each party's" do
      wire = compile!(Fude.parliament(@results, color: :party, value: :seats, majority: 106))

      assert wire["description"] =~
               "A parliament chart. 211 seats, 106 for a majority: Social 83, Forward! 73, Alliance 55."

      assert {["Party", "Value"], [["Social", 83] | _]} = Compile.table(wire)
    end

    test "a majority is a whole number above 0, of any size" do
      assert %{options: %{majority: 2000}} =
               hd(Fude.parliament(color: :p, value: :s, majority: 2000).layers)

      assert_raise ArgumentError,
                   ~r/:majority of a parliament chart must be a whole number above 0/,
                   fn ->
                     Fude.parliament(color: :p, value: :s, majority: 0)
                   end
    end

    test "loads as it was dumped" do
      chart =
        Fude.parliament(color: [field: :party, sort: ["B", "A"]], value: :seats, majority: 116)

      assert {:ok, chart} ==
               chart |> Fude.Spec.dump() |> JSON.encode!() |> JSON.decode!() |> Fude.Spec.load()
    end
  end

  describe "bars colored by their own categories" do
    test "are not a stack of one segment each, and have no legend" do
      wire = compile!(Fude.bar(@results, x: :party, y: :seats, color: :party, horizontal: true))
      assert layer(wire)["stack"] == nil
      assert wire["scales"]["color"]["legend"] == false
    end

    test "a color of another field still stacks, with its legend" do
      rows =
        for r <- @results,
            kind <- ["Seats", "Votes"],
            do: %{party: r.party, kind: kind, v: r.seats}

      wire = compile!(Fude.bar(rows, x: :party, y: :v, color: :kind))
      assert layer(wire)["stack"] == "zero"
      refute Map.has_key?(wire["scales"]["color"], "legend")
    end
  end

  describe "labels: :series" do
    test "names each segment by its series" do
      wire =
        compile!(
          Fude.bar(@results,
            x: :party,
            y: [field: :seats, stack: :normalize],
            color: :party,
            labels: :series
          )
        )

      assert layer(wire)["options"]["labels"] == "series"
    end

    test "is one of true, false and :series" do
      assert_raise ArgumentError,
                   ~r/:labels of a bar chart must be one of true, false, :series/,
                   fn ->
                     Fude.bar(x: :a, y: :b, labels: :names)
                   end
    end
  end

  test "a column of changes says so to the browser" do
    wire =
      compile!(
        Fude.layers(@results, [
          Fude.bar(x: :party, y: :seats, horizontal: true),
          Fude.text(y: :party, text: :change, change: true),
          Fude.text(y: :party, text: :votes)
        ])
      )

    assert %{"column" => true, "change" => true} = layer(wire, 1)["options"]
    refute Map.has_key?(layer(wire, 2)["options"], "change")
  end

  test "a line at an x on one category of y keeps both" do
    wire =
      compile!(
        Fude.bar(@results,
          x: :party,
          y: [field: :seats, stack: :normalize],
          color: :party,
          horizontal: true
        )
        |> Fude.annotate(:line, x: 0.5, y: "Social", text: "Half")
      )

    assert [%{"type" => "line", "x" => 0.5, "y" => 0, "text" => "Half"}] = wire["annotations"]
  end

  describe "a map shaded by a number" do
    @leads [
      %{state: "CA", leader: "Social", lead: 12.5},
      %{state: "TX", leader: "Forward!", lead: 3.1}
    ]

    test "its colors by a category, their shade by a number, with a scale of its own" do
      wire =
        compile!(
          Fude.choropleth(@leads,
            region: :state,
            color: :leader,
            shade: [field: :lead, title: "Lead"],
            map: "us-states"
          )
        )

      assert %{"type" => "ordinal", "domain" => ["Social", "Forward!"]} = wire["scales"]["color"]

      assert %{"type" => "linear", "domain" => [3.1, 12.5], "title" => "Lead"} =
               wire["scales"]["shade"]

      assert layer(wire)["columns"]["shade"] == [12.5, 3.1]
    end

    test "its table names each region, with its color and its shade" do
      wire =
        compile!(
          Fude.choropleth(@leads, region: :state, color: :leader, shade: :lead, map: "us-states")
        )

      assert Compile.table(wire) ==
               {["State", "Leader", "Lead"], [["CA", "Social", 12.5], ["TX", "Forward!", 3.1]]}
    end

    test "a map's table names its regions" do
      wire =
        compile!(Fude.choropleth([%{country: "PRT", users: 10}], region: :country, color: :users))

      assert Compile.table(wire) == {["Country", "Users"], [["PRT", 10]]}
    end
  end
end
