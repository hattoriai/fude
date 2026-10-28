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

  test "select names the event a click on a mark sends" do
    assigns = %{chart: Fude.bar(@sales, x: :region, y: :revenue)}

    html =
      rendered_to_string(
        ~H|<.chart id="revenue" chart={@chart} select="pick" phx-target="#box" />|
      )

    doc = LazyHTML.from_fragment(html)

    assert Enum.count(
             LazyHTML.query(doc, ~s|figure#revenue[data-fude-select="pick"][phx-target="#box"]|)
           ) == 1

    html = rendered_to_string(~H|<.chart id="revenue" chart={@chart} />|)
    assert LazyHTML.query(LazyHTML.from_fragment(html), "[data-fude-select]") |> Enum.empty?()
  end

  test "selected names the marks that stand out, as JSON; none leaves it out" do
    assigns = %{chart: Fude.bar(@sales, x: :region, y: :revenue)}

    html =
      rendered_to_string(~H|<.chart id="revenue" chart={@chart} selected={%{"x" => "North"}} />|)

    [selected] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("figure")
      |> LazyHTML.attribute("data-fude-selected")

    assert JSON.decode!(selected) == %{"x" => "North"}

    html = rendered_to_string(~H|<.chart id="revenue" chart={@chart} selected={%{}} />|)
    assert LazyHTML.query(LazyHTML.from_fragment(html), "[data-fude-selected]") |> Enum.empty?()
  end

  test "link names the charts that show a hover together; none leaves it out" do
    assigns = %{chart: Fude.bar(@sales, x: :region, y: :revenue)}

    html = rendered_to_string(~H|<.chart id="revenue" chart={@chart} link="regions" />|)
    doc = LazyHTML.from_fragment(html)
    assert Enum.count(LazyHTML.query(doc, ~s|figure#revenue[data-fude-link="regions"]|)) == 1

    html = rendered_to_string(~H|<.chart id="revenue" chart={@chart} />|)
    assert LazyHTML.query(LazyHTML.from_fragment(html), "[data-fude-link]") |> Enum.empty?()
  end

  test "each panel of small multiples is in the chart's link" do
    rows = for r <- ["A", "B"], m <- 1..3, do: %{r: r, m: m, v: m * 2}
    assigns = %{chart: rows |> Fude.line(x: :m, y: :v) |> Fude.facet(:r)}

    html = rendered_to_string(~H|<.chart id="by-r" chart={@chart} link="months" />|)
    doc = LazyHTML.from_fragment(html)

    assert Enum.count(
             LazyHTML.query(doc, ~s|.fude-panel[phx-hook="Fude"][data-fude-link="months"]|)
           ) ==
             2
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

  test "a trend with a spark draws its history under it, ending on its value" do
    months = [
      %{month: ~D[2026-03-01], mrr: 300, last: 280},
      %{month: ~D[2026-01-01], mrr: 100, last: 280},
      %{month: ~D[2026-02-01], mrr: 200, last: 280}
    ]

    assigns = %{chart: Fude.trend(months, value: :mrr, compare: :last, spark: :month)}
    html = rendered_to_string(~H|<.chart id="mrr" chart={@chart} />|)
    doc = LazyHTML.from_fragment(html)

    assert [_] = doc |> LazyHTML.query(".fude-spark[aria-hidden=true]") |> Enum.to_list()
    # In the order of the months: 100, 200, 300, up to the top.
    assert [line] = doc |> LazyHTML.query(".fude-spark-line") |> LazyHTML.attribute("d")
    assert line == "M0.0,30.0 50.0,16.0 100.0,2.0"
    assert LazyHTML.attribute(LazyHTML.query(doc, ".fude-spark-last"), "style") == ["top: 6.25%"]
  end

  test "a spark needs two points, and a number without one has none" do
    assigns = %{
      one: Fude.number([%{d: ~D[2026-01-01], v: 1}], value: :v, spark: :d),
      none: Fude.number([%{v: 1}, %{v: 2}], value: :v)
    }

    refute rendered_to_string(~H|<.chart id="a" chart={@one} />|) =~ "fude-spark"
    refute rendered_to_string(~H|<.chart id="b" chart={@none} />|) =~ "fude-spark"
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
