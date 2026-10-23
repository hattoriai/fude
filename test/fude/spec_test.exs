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

      assert %{"layers" => [%{"kind" => "line"}, %{"kind" => "rule", "y" => %{"value" => 1000}, "label" => "Goal"}]} =
               Spec.dump(chart)
    end

    test "writes a currency as code" do
      chart = Fude.bar(x: :region, y: [field: :revenue, format: {:currency, "EUR"}])
      assert %{"y" => %{"format" => "currency:EUR"}} = Spec.dump(chart)
    end

    test "holds the data only when asked" do
      chart = Fude.bar([%{region: "North", revenue: 10}], x: :region, y: :revenue)
      refute Map.has_key?(Spec.dump(chart), "datasets")
      assert %{"datasets" => %{"data" => [%{"region" => "North", "revenue" => 10}]}} = Spec.dump(chart, data: true)
    end

    test "is JSON as it is" do
      chart = Fude.histogram(x: [field: :total, bin: [count: 30], title: "Total"], title: "Orders")
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

      assert {:ok, ^chart} = chart |> Spec.dump() |> JSON.encode!() |> JSON.decode!() |> Spec.load()
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

      assert %{path: ["y", "aggregate"], message: message} = Enum.find(errors, &(&1.path == ["y", "aggregate"]))
      assert message =~ ~s|did you mean "sum"?|

      assert %{message: message} = Enum.find(errors, &(&1.path == ["colour"]))
      assert message =~ ~s|did you mean "color"?|
    end

    test "names a missing channel" do
      assert {:error, [%{path: ["y"], message: "is missing: a bar chart needs it"}]} =
               Spec.load(%{"fude" => 1, "kind" => "bar", "x" => "region"})
    end

    test "refuses a spec with no version or a newer one" do
      assert {:error, [%{path: ["fude"], message: "is missing" <> _}]} = Spec.load(%{"kind" => "bar"})
      assert {:error, [%{path: ["fude"], message: "is version 9" <> _}]} = Spec.load(%{"fude" => 9})
    end

    test "refuses an unknown kind, with a suggestion" do
      assert {:error, [%{path: ["kind"], message: message}]} = Spec.load(%{"fude" => 1, "kind" => "lines"})
      assert message =~ ~s|did you mean "line"?|
    end
  end

  describe "the round trip" do
    property "load(dump(chart)) is the chart" do
      check all chart <- chart() do
        assert {:ok, chart} == chart |> Spec.dump() |> JSON.encode!() |> JSON.decode!() |> Spec.load()
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
      map({field(), member_of([:compact, :percent, {:currency, "EUR"}]), member_of(["A title", false])}, fn {f, format, title} ->
        [field: f, format: format, title: title]
      end)
    ])
  end

  defp chart do
    gen all kind <- member_of([:bar, :line, :area, :scatter, :heatmap]),
            x <- channel(),
            y <- channel(),
            color <- one_of([constant(nil), channel()]),
            title <- one_of([constant(nil), string(:printable, max_length: 20)]) do
      opts = [x: x, y: y, title: title] ++ if(color, do: [color: color], else: [])
      apply(Fude, kind, [opts])
    end
  end
end

defmodule Fude.SpecAtomsTest do
  # Alone (not async), so that no other test makes atoms meanwhile.
  use ExUnit.Case, async: false

  test "load/1 makes no atom of what a spec says" do
    spec = fn key -> %{"fude" => 1, "kind" => key, "x" => %{"field" => "a", key => key}, key => 1} end
    Fude.Spec.load(spec.("warm-up"))
    before = :erlang.system_info(:atom_count)
    Fude.Spec.load(spec.("fresh_key_#{System.unique_integer([:positive])}"))
    assert :erlang.system_info(:atom_count) == before
  end
end
