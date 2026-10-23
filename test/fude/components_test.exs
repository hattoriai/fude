defmodule Fude.ComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Fude.Components

  @sales [%{region: "North", revenue: 120}, %{region: "South", revenue: 60}]

  test "renders the words, the plot and the table" do
    assigns = %{
      chart: Fude.bar(@sales, x: :region, y: :revenue, title: "Revenue", source: "Ledger")
    }

    html = rendered_to_string(~H|<.chart id="revenue" chart={@chart} />|)
    doc = LazyHTML.from_fragment(html)

    assert Enum.count(LazyHTML.query(doc, ~s|figure#revenue[phx-hook="Fude"][data-fude]|)) == 1
    assert LazyHTML.text(LazyHTML.query(doc, ".fude-title")) == "Revenue"
    assert LazyHTML.text(LazyHTML.query(doc, ".fude-source")) == "Ledger"

    assert Enum.count(LazyHTML.query(doc, ~s|#revenue-plot[phx-update="ignore"][role="img"]|)) ==
             1

    assert LazyHTML.text(LazyHTML.query(doc, "tbody tr:first-child")) =~ "North"
  end

  test "draws a saved spec with its data again" do
    spec = Fude.Spec.dump(Fude.bar(x: :region, y: :revenue))
    assigns = %{spec: spec, data: @sales}
    html = rendered_to_string(~H|<.chart id="revenue" spec={@spec} data={@data} />|)
    assert html =~ "North"
    refute html =~ "fude-error"
  end

  test "shows why a chart cannot draw, and does not raise" do
    assigns = %{spec: %{"fude" => 1, "kind" => "bar", "x" => "region"}}
    html = rendered_to_string(~H|<.chart id="broken" spec={@spec} data={[]} />|)
    assert html =~ "fude-error"
    assert html =~ "a bar chart needs it"
  end

  test "writes a single number on the server" do
    assigns = %{chart: Fude.progress([%{done: 68}], value: :done, goal: 80, label: "Done")}
    html = rendered_to_string(~H|<.chart id="done" chart={@chart} />|)
    doc = LazyHTML.from_fragment(html)
    assert LazyHTML.attribute(LazyHTML.query(doc, "data.fude-value"), "value") == ["68"]

    assert LazyHTML.attribute(LazyHTML.query(doc, "[role=progressbar]"), "aria-valuenow") == [
             "68"
           ]

    assert html =~ "width: 85.0%"
  end

  test "needs a chart or a spec" do
    assigns = %{}

    assert_raise ArgumentError, ~r/needs a chart or a spec/, fn ->
      rendered_to_string(~H|<.chart id="x" />|)
    end
  end

  test "draws a gauge on the server, as a meter" do
    assigns = %{chart: Fude.gauge([%{p: 75}], value: :p, target: 90, label: "Score")}
    html = rendered_to_string(~H|<.chart id="score" chart={@chart} />|)
    doc = LazyHTML.from_fragment(html)
    assert LazyHTML.attribute(LazyHTML.query(doc, "[role=meter]"), "aria-valuenow") == ["75"]
    assert Enum.count(LazyHTML.query(doc, "path.fude-gauge-value")) == 1
    assert Enum.count(LazyHTML.query(doc, "line.fude-gauge-target")) == 1
  end
end
