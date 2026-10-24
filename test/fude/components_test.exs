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

  test "the data table keeps its open as the LiveView renders it again" do
    assigns = %{chart: Fude.bar(@sales, x: :region, y: :revenue)}
    html = rendered_to_string(~H|<.chart id="revenue" chart={@chart} />|)

    [mounted] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("details.fude-data")
      |> LazyHTML.attribute("phx-mounted")

    assert mounted =~ "ignore_attrs"
    assert mounted =~ ~s|"open"|
  end

  test "table={:swap} puts the data in the plot's place, behind a Data button" do
    assigns = %{chart: Fude.bar(@sales, x: :region, y: :revenue)}

    doc =
      LazyHTML.from_fragment(
        rendered_to_string(~H|<.chart id="revenue" chart={@chart} table={:swap} />|)
      )

    assert Enum.count(LazyHTML.query(doc, ".fude-frame > #revenue-plot.fude-plot")) == 1

    assert LazyHTML.text(
             LazyHTML.query(
               doc,
               ".fude-frame > #revenue-data.fude-data-over tbody tr:first-child"
             )
           ) =~ "North"

    assert Enum.empty?(LazyHTML.query(doc, "details.fude-data"))

    [button] =
      LazyHTML.query(
        doc,
        ~s|.fude-data-toggle button[aria-controls="revenue-data"][aria-pressed="false"]|
      )
      |> Enum.to_list()

    assert LazyHTML.text(button) =~ "Data"
    [mounted] = LazyHTML.attribute(LazyHTML.query(doc, "figure#revenue"), "phx-mounted")
    assert mounted =~ "data-fude-data"
  end

  test "table={false} leaves the data out; a single value has no table to swap" do
    assigns = %{
      chart: Fude.bar(@sales, x: :region, y: :revenue),
      number: Fude.number([%{n: 3}], value: :n)
    }

    none =
      LazyHTML.from_fragment(
        rendered_to_string(~H|<.chart id="r" chart={@chart} table={false} />|)
      )

    assert Enum.empty?(LazyHTML.query(none, "table"))
    assert Enum.empty?(LazyHTML.query(none, ".fude-data-toggle"))

    single =
      LazyHTML.from_fragment(
        rendered_to_string(~H|<.chart id="n" chart={@number} table={:swap} />|)
      )

    assert Enum.empty?(LazyHTML.query(single, ".fude-frame, .fude-data-toggle"))
  end

  test "table takes true, false, :below or :swap" do
    assigns = %{chart: Fude.bar(@sales, x: :region, y: :revenue), table: :side}

    assert_raise ArgumentError, ~r/table must be/, fn ->
      rendered_to_string(~H|<.chart id="r" chart={@chart} table={@table} />|)
    end
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
    assert LazyHTML.attribute(LazyHTML.query(doc, "data.fude-share"), "value") == ["0.85"]
    assert LazyHTML.text(LazyHTML.query(doc, ".fude-progress-head .fude-label")) == "Done"
  end

  test "centers a single value in a box of the chart's height, sized by its characters" do
    assigns = %{chart: Fude.number([%{n: 1234}], value: :n, label: "Orders")}
    html = rendered_to_string(~H|<.chart id="orders" chart={@chart} height={200} />|)
    doc = LazyHTML.from_fragment(html)
    single = LazyHTML.query(doc, ".fude-single.fude-single-center")
    assert LazyHTML.attribute(single, "style") == ["height: 200px"]

    assert LazyHTML.attribute(LazyHTML.query(doc, "data.fude-value"), "style") == [
             "--fude-chars: 4"
           ]
  end

  test "sets a single value at the start, at its own size, when asked" do
    assigns = %{chart: Fude.number([%{n: 1}], value: :n, align: :start)}
    html = rendered_to_string(~H|<.chart id="n" chart={@chart} height={200} />|)
    doc = LazyHTML.from_fragment(html)
    assert Enum.count(LazyHTML.query(doc, ".fude-single.fude-single-start")) == 1
    refute html =~ "height: 200px"
  end

  test "writes a trend's change with the digits of its value" do
    assigns = %{
      chart:
        Fude.trend([%{n: 110, last: 100}],
          value: [field: :n, format: :number, digits: 0],
          compare: :last
        )
    }

    html = rendered_to_string(~H|<.chart id="t" chart={@chart} />|)
    doc = LazyHTML.from_fragment(html)
    delta = LazyHTML.query(doc, ".fude-delta data")
    assert LazyHTML.attribute(delta, "data-format") == ["percent-change:0"]
    assert LazyHTML.text(delta) =~ "+10%"
  end

  test "writes a trend's change as a pill before its label" do
    assigns = %{
      chart: Fude.trend([%{n: 110, last: 100}], value: :n, compare: :last, label: "vs May")
    }

    html = rendered_to_string(~H|<.chart id="t" chart={@chart} />|)
    doc = LazyHTML.from_fragment(html)
    assert LazyHTML.text(LazyHTML.query(doc, ".fude-meta .fude-delta.fude-up")) =~ "+10.0%"
    assert LazyHTML.text(LazyHTML.query(doc, ".fude-meta .fude-label")) == "vs May"
  end

  test "a sparkline with no height fills its box; with one, it has that height" do
    days = for d <- 1..5, do: %{d: d, v: d}
    assigns = %{chart: Fude.sparkline(days, x: :d, y: :v)}
    html = rendered_to_string(~H|<.chart id="s" chart={@chart} />|)
    assert html =~ ~s(class="fude-plot fude-plot-fill")
    assert html =~ "min-height: 48px"

    html = rendered_to_string(~H|<.chart id="s" chart={@chart} height={80} />|)
    refute html =~ "fude-plot-fill"
    assert html =~ "height: 80px"
  end

  test "height={:fill} fills the box, at least 120 pixels high; another height raises" do
    assigns = %{chart: Fude.bar([%{r: "A", v: 1}], x: :r, y: :v)}
    html = rendered_to_string(~H|<.chart id="c" chart={@chart} height={:fill} />|)
    assert html =~ ~s(class="fude-plot fude-plot-fill")
    assert html =~ "min-height: 120px"

    html = rendered_to_string(~H|<.chart id="c" chart={@chart} height={:fill} table={:swap} />|)
    assert html =~ "fude-frame fude-frame-fill"

    assert_raise ArgumentError, ~r/height must be a positive integer or :fill/, fn ->
      rendered_to_string(~H|<.chart id="c" chart={@chart} height={:auto} />|)
    end
  end

  test "a single value with height={:fill} fills its box" do
    assigns = %{chart: Fude.number([%{v: 3}], value: :v)}
    html = rendered_to_string(~H|<.chart id="n" chart={@chart} height={:fill} />|)
    assert html =~ "fude-single-center"
    refute html =~ "height: "
  end

  test "the shared legend of small multiples takes the color's scheme" do
    rows = for r <- ~w(N S), c <- ~w(a b), do: %{r: r, c: c, m: 1, v: 2}

    assigns = %{
      chart:
        Fude.bar(rows, x: :m, y: :v, color: [field: :c, scheme: ["#123456", "#abcdef"]])
        |> Fude.facet(:r)
    }

    html = rendered_to_string(~H|<.chart id="f" chart={@chart} />|)
    assert html =~ "background: #123456"
    assert html =~ "background: #abcdef"
  end

  test "the component's animate is over the chart's (#16)" do
    rows = [%{r: "a", v: 1}]
    assigns = %{chart: Fude.bar(rows, x: :r, y: :v, animate: [duration: 900])}

    config = fn html ->
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("figure")
      |> LazyHTML.attribute("data-fude")
      |> hd()
      |> JSON.decode!()
    end

    assert config.(rendered_to_string(~H|<.chart id="a" chart={@chart} />|))["animate"] == %{
             "duration" => 900
           }

    assert config.(rendered_to_string(~H|<.chart id="a" chart={@chart} animate={false} />|))[
             "animate"
           ] == false

    refute Map.has_key?(
             config.(rendered_to_string(~H|<.chart id="a" chart={@chart} animate />|)),
             "animate"
           )
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
    assert Enum.count(LazyHTML.query(doc, ".fude-dial data.fude-value")) == 1
  end
end
