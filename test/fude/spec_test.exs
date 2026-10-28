defmodule Fude.SpecTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Fude.Spec

  describe "dump/2" do
    test "puts a chart of one layer at the top, a field as its name" do
      chart = Fude.bar(x: :region, y: {:sum, :revenue}, color: :channel, title: "Revenue")

      assert Spec.dump(chart) == %{
               "fude" => 1,
               "kind" => "bar",
               "title" => "Revenue",
               "x" => "region",
               "y" => %{"field" => "revenue", "aggregate" => "sum"},
               "color" => "channel"
             }
    end

    test "puts the layers of a chart of several in a list" do
      chart = Fude.layers(nil, [Fude.line(x: :day, y: :count), Fude.rule(y: 1000, label: "Goal")])

      assert %{
               "layers" => [
                 %{"kind" => "line"},
                 %{"kind" => "rule", "y" => %{"value" => 1000}, "label" => "Goal"}
               ]
             } =
               Spec.dump(chart)
    end

    test "writes and reads the right axis of a channel" do
      chart =
        Fude.layers(nil, [
          Fude.bar(x: :day, y: :orders),
          Fude.line(x: :day, y: [field: :revenue, axis: :right])
        ])

      spec = Spec.dump(chart)
      assert %{"layers" => [_, %{"y" => %{"field" => "revenue", "axis" => "right"}}]} = spec
      assert Spec.load(spec) == {:ok, chart}

      assert {:error, [%{path: ["y", "axis"], message: message}]} =
               Spec.load(%{
                 "fude" => 1,
                 "kind" => "line",
                 "x" => "day",
                 "y" => %{"field" => "n", "axis" => "rihgt"}
               })

      assert message =~ ~s(did you mean "right"?)
    end

    test "writes and reads the align of a single value; a spec without it centers" do
      chart = Fude.number(nil, value: :mrr, align: :start)
      spec = Spec.dump(chart)
      assert %{"kind" => "number", "align" => "start"} = spec
      assert Spec.load(spec) == {:ok, chart}

      assert {:ok, %Fude.Chart{layers: [%{options: options}]}} =
               Spec.load(%{"fude" => 1, "kind" => "gauge", "value" => "p"})

      refute Map.has_key?(options, :align)

      assert {:error, [%{path: ["align"]}]} =
               Spec.load(%{"fude" => 1, "kind" => "trend", "value" => "n", "align" => "left"})
    end

    test "writes and reads a channel's digits" do
      chart = Fude.number(nil, value: [field: :revenue, format: :number, digits: 0])
      spec = Spec.dump(chart)
      assert %{"value" => %{"field" => "revenue", "format" => "number", "digits" => 0}} = spec
      assert Spec.load(spec) == {:ok, chart}

      assert {:error, [%{path: ["value", "digits"], message: message}]} =
               Spec.load(%{
                 "fude" => 1,
                 "kind" => "number",
                 "value" => %{"field" => "n", "digits" => 1.5}
               })

      assert message =~ "a whole number from 0 to 20"
    end

    test "writes and reads a scheme, its middle, and a list of colors" do
      for color <- [
            [field: :margin, scheme: :red_blue, mid: 5],
            [field: :status, scheme: ["#0b6e4f", "#f2c14e", "#d1495b"]]
          ] do
        chart = Fude.heatmap(nil, x: :a, y: :b, color: color)
        assert Spec.load(Spec.dump(chart)) == {:ok, chart}
      end

      assert %{"color" => %{"scheme" => "red_blue", "mid" => 5}} =
               Spec.dump(
                 Fude.heatmap(nil, x: :a, y: :b, color: [field: :m, scheme: :red_blue, mid: 5])
               )

      assert {:error, [%{path: ["color", "scheme"], message: message}]} =
               Spec.load(%{
                 "fude" => 1,
                 "kind" => "heatmap",
                 "x" => "a",
                 "y" => "b",
                 "color" => %{"field" => "m", "scheme" => "virdis"}
               })

      assert message =~ ~s(did you mean "viridis"?)

      assert {:error, [%{path: ["color", "scheme"]}]} =
               Spec.load(%{
                 "fude" => 1,
                 "kind" => "heatmap",
                 "x" => "a",
                 "y" => "b",
                 "color" => %{"field" => "m", "scheme" => ["red; background: url(x)", "#fff"]}
               })
    end

    test "writes and reads a funnel's and a sparkline's options; saved ones are unchanged" do
      for chart <- [
            Fude.funnel(nil, x: :stage, y: :people, color: :stage, step: true, labels: :inside),
            Fude.funnel(nil, x: :stage, y: :people, labels: false),
            Fude.sparkline(nil, x: :day, y: :visits, area: true, points: :extremes, value: true)
          ] do
        assert Spec.load(Spec.dump(chart)) == {:ok, chart}
      end

      assert {:ok, %Fude.Chart{layers: [%{options: options}]}} =
               Spec.load(%{"fude" => 1, "kind" => "sparkline", "x" => "d", "y" => "v"})

      assert options == %{}
    end

    test "writes what a tooltip adds at the end of its list, and reads it back (#15)" do
      chart = Fude.bar(nil, x: :month, y: :revenue, tooltip: [:plan, change: true, history: true])
      assert %{"tooltip" => ["plan", %{"change" => true, "history" => true}]} = Spec.dump(chart)
      assert Spec.load(Spec.dump(chart)) == {:ok, chart}

      chart = Fude.area(nil, x: :month, y: :revenue, color: :channel, tooltip: [share: false])
      assert %{"tooltip" => [%{"share" => false}]} = Spec.dump(chart)
      assert Spec.load(Spec.dump(chart)) == {:ok, chart}

      assert {:error, [%{path: ["tooltip", 1], message: message}]} =
               Spec.load(%{
                 "fude" => 1,
                 "kind" => "bar",
                 "x" => "m",
                 "y" => "r",
                 "tooltip" => ["plan", %{"change" => true, "rnak" => true}]
               })

      assert message =~ ~s(did you mean "rank"?)
    end

    test "writes and reads a chart's animate and frame (#16); saved charts animate" do
      for chart <- [
            Fude.bar(nil, x: :r, y: :v, animate: false),
            Fude.bar(nil, x: :r, y: :v, animate: [duration: 800], frame: "May 2026")
          ] do
        assert Spec.load(Spec.dump(chart)) == {:ok, chart}
      end

      assert %{"animate" => %{"duration" => 800}, "frame" => "May 2026"} =
               Spec.dump(Fude.bar(nil, x: :r, y: :v, animate: [duration: 800], frame: "May 2026"))

      refute Map.has_key?(Spec.dump(Fude.bar(nil, x: :r, y: :v)), "animate")

      assert {:error, [%{path: ["animate"]}]} =
               Spec.load(%{
                 "fude" => 1,
                 "kind" => "bar",
                 "x" => "r",
                 "y" => "v",
                 "animate" => "slow"
               })
    end

    test "writes a currency as code" do
      chart = Fude.bar(x: :region, y: [field: :revenue, format: {:currency, "EUR"}])
      assert %{"y" => %{"format" => "currency:EUR"}} = Spec.dump(chart)
    end

    test "holds the data only when asked" do
      chart = Fude.bar([%{region: "North", revenue: 10}], x: :region, y: :revenue)
      refute Map.has_key?(Spec.dump(chart), "datasets")

      assert %{"datasets" => %{"data" => [%{"region" => "North", "revenue" => 10}]}} =
               Spec.dump(chart, data: true)
    end

    test "is JSON as it is" do
      chart =
        Fude.histogram(x: [field: :total, bin: [count: 30], title: "Total"], title: "Orders")

      spec = Spec.dump(chart)
      assert spec |> JSON.encode!() |> JSON.decode!() == spec
    end
  end

  describe "load/1" do
    test "takes back what dump gave" do
      chart =
        Fude.line(
          x: {:week, :day},
          y: [field: :visits, aggregate: :sum, format: :compact, scale: [zero: true]],
          color: [field: :source, sort: ["Search", "Direct"]],
          curve: :monotone,
          title: "Visits",
          caption: "Weekly",
          height: 280
        )

      assert {:ok, ^chart} =
               chart |> Spec.dump() |> JSON.encode!() |> JSON.decode!() |> Spec.load()
    end

    test "gives every error, each where it is, with a suggestion" do
      spec = %{
        "fude" => 1,
        "kind" => "bar",
        "x" => "region",
        "y" => %{"field" => "revenue", "aggregate" => "summ"},
        "colour" => "channel"
      }

      assert {:error, errors} = Spec.load(spec)

      assert %{path: ["y", "aggregate"], message: message} =
               Enum.find(errors, &(&1.path == ["y", "aggregate"]))

      assert message =~ ~s|did you mean "sum"?|

      assert %{message: message} = Enum.find(errors, &(&1.path == ["colour"]))
      assert message =~ ~s|did you mean "color"?|
    end

    test "takes back a dumbbell: joined points, their labels, suffixes and a column of text" do
      chart =
        Fude.layers(nil, [
          Fude.scatter(
            x: [field: :rate, format: :decimal_bytes, suffix: "/s", scale: [type: :log]],
            y: :bench,
            color: :parser,
            connect: true,
            labels: true
          ),
          Fude.text(y: :bench, text: [field: :speedup, digits: 1, suffix: "×"])
        ])

      spec = Spec.dump(chart)

      assert %{
               "layers" => [
                 %{"connect" => true, "labels" => true, "x" => %{"suffix" => "/s"}},
                 %{"text" => %{"suffix" => "×"}}
               ]
             } = spec

      assert {:ok, ^chart} = spec |> JSON.encode!() |> JSON.decode!() |> Spec.load()
    end

    test "a suffix is short words, and connect true or false" do
      spec = %{
        "fude" => 1,
        "kind" => "scatter",
        "x" => %{"field" => "rate", "suffix" => 5},
        "y" => "bench",
        "connect" => "yes"
      }

      assert {:error, errors} = Spec.load(spec)

      assert %{message: "must be a string of 1 to 16" <> _} =
               Enum.find(errors, &(&1.path == ["x", "suffix"]))

      assert Enum.find(errors, &(&1.path == ["connect"]))
    end

    test "takes back a highlight, and refuses what is not one" do
      chart =
        Fude.line(x: :month, y: :revenue, color: [field: :channel, highlight: ["Online", 2026]])

      assert %{"color" => %{"highlight" => ["Online", 2026]}} = Spec.dump(chart)

      assert {:ok, ^chart} =
               chart |> Spec.dump() |> JSON.encode!() |> JSON.decode!() |> Spec.load()

      assert {:error, [%{path: ["color", "highlight"]}]} =
               Spec.load(%{
                 "fude" => 1,
                 "kind" => "line",
                 "x" => "m",
                 "y" => "v",
                 "color" => %{"field" => "c", "highlight" => %{"a" => 1}}
               })
    end

    test "takes back a brush, and refuses another" do
      chart = Fude.line(x: :day, y: :visits, brush: :select)
      assert %{"brush" => "select"} = Spec.dump(chart)

      assert {:ok, ^chart} =
               chart |> Spec.dump() |> JSON.encode!() |> JSON.decode!() |> Spec.load()

      refute Map.has_key?(Spec.dump(Fude.line(x: :day, y: :visits)), "brush")

      assert {:error, [%{path: ["brush"], message: message}]} =
               Spec.load(%{
                 "fude" => 1,
                 "kind" => "line",
                 "x" => "day",
                 "y" => "visits",
                 "brush" => "pan"
               })

      assert message =~ ~s|must be "zoom", "select" or false|
    end

    test "names a missing channel" do
      assert {:error, [%{path: ["y"], message: "is missing: a bar chart needs it"}]} =
               Spec.load(%{"fude" => 1, "kind" => "bar", "x" => "region"})
    end

    test "refuses a spec with no version or a newer one" do
      assert {:error, [%{path: ["fude"], message: "is missing" <> _}]} =
               Spec.load(%{"kind" => "bar"})

      assert {:error, [%{path: ["fude"], message: "is version 9" <> _}]} =
               Spec.load(%{"fude" => 9})
    end

    test "refuses an unknown kind, with a suggestion" do
      assert {:error, [%{path: ["kind"], message: message}]} =
               Spec.load(%{"fude" => 1, "kind" => "lines"})

      assert message =~ ~s|did you mean "line"?|
    end
  end

  describe "the round trip" do
    property "load(dump(chart)) is the chart" do
      check all(chart <- chart()) do
        assert {:ok, chart} ==
                 chart |> Spec.dump() |> JSON.encode!() |> JSON.decode!() |> Spec.load()
      end
    end
  end

  defp field, do: member_of(~w(region revenue day source total count))

  defp channel do
    one_of([
      field(),
      tuple({member_of(Fude.Channel.aggregates()), field()}),
      tuple({member_of(Fude.Channel.time_units()), field()}),
      tuple({constant(:bin), field()}),
      map(
        {field(), member_of([:compact, :percent, :decimal_bytes, {:currency, "EUR"}]),
         member_of(["A title", false]), member_of([nil, "×", "/s"])},
        fn {f, format, title, suffix} ->
          [field: f, format: format, title: title] ++ if(suffix, do: [suffix: suffix], else: [])
        end
      )
    ])
  end

  defp chart do
    gen all(
          kind <- member_of([:bar, :line, :area, :scatter, :heatmap]),
          x <- channel(),
          y <- channel(),
          color <- one_of([constant(nil), channel()]),
          title <- one_of([constant(nil), string(:printable, max_length: 20)])
        ) do
      opts = [x: x, y: y, title: title] ++ if(color, do: [color: color], else: [])
      apply(Fude, kind, [opts])
    end
  end
end

defmodule Fude.SpecAtomsTest do
  # Alone (not async), so that no other test makes atoms meanwhile.
  use ExUnit.Case, async: false

  test "load/1 makes no atom of what a spec says" do
    spec = fn key ->
      %{"fude" => 1, "kind" => key, "x" => %{"field" => "a", key => key}, key => 1}
    end

    Fude.Spec.load(spec.("warm-up"))
    before = :erlang.system_info(:atom_count)
    Fude.Spec.load(spec.("fresh_key_#{System.unique_integer([:positive])}"))
    assert :erlang.system_info(:atom_count) == before
  end

  test "layers and annotations keep their ids; an id is text" do
    spec = %{
      "fude" => 1,
      "layers" => [%{"id" => "l1", "kind" => "bar", "x" => "region", "y" => "revenue"}],
      "annotations" => [%{"id" => "n1", "type" => "line", "y" => 100, "text" => "Goal"}]
    }

    assert {:ok, chart} = Fude.Spec.load(spec)
    assert Fude.Spec.dump(chart, layers: true) == spec

    assert {:error, [%{path: ["layers", 0, "id"], message: "must be text, got: 7"}]} =
             Fude.Spec.load(put_in(spec, ["layers", Access.at(0), "id"], 7))
  end

  test "a trend's spark is in its spec" do
    rows = [%{d: ~D[2026-01-01], v: 1}, %{d: ~D[2026-02-01], v: 2}]
    chart = Fude.trend(rows, value: :v, spark: :d)
    spec = Fude.Spec.dump(chart)
    assert inspect(spec) =~ ~s("spark")

    assert {:ok, loaded} = Fude.Spec.load(spec)
    assert Fude.Spec.dump(loaded) == spec
  end
end
