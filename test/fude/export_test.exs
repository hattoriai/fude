defmodule Fude.ExportTest do
  use ExUnit.Case, async: true

  alias Fude.Export

  @sales [
    %{region: "North", revenue: 120, channel: "Online"},
    %{region: "South", revenue: 90.5, channel: "Retail"}
  ]

  defp revenue do
    Fude.bar(@sales,
      x: :region,
      y: :revenue,
      color: :channel,
      title: "Revenue",
      subtitle: "By region",
      caption: "Draft.",
      source: "Ledger"
    )
  end

  describe "to_markdown/2" do
    test "writes the words and the data as a table, numbers aligned right" do
      assert Export.to_markdown(revenue()) == """
             **Revenue**

             *By region*

             | Region | Revenue | Channel |
             | --- | ---: | --- |
             | North | 120 | Online |
             | South | 90.5 | Retail |

             Draft. Source: Ledger
             """
    end

    test "Fude.to_markdown/2 is the same" do
      assert Fude.to_markdown(revenue()) == Export.to_markdown(revenue())
    end

    test "writes Markdown's own characters in words as they are" do
      chart = Fude.bar([%{name: "A|B *x*\nnext", n: 1}], x: :name, y: :n, title: "a_b [c]")

      assert Export.to_markdown(chart) == """
             **a\\_b \\[c\\]**

             | Name | N |
             | --- | ---: |
             | A\\|B \\*x\\* next | 1 |
             """
    end

    test "writes the notes on the data, with where they are" do
      chart =
        revenue()
        |> Fude.annotate(:label, x: "North", y: 120, text: "Best quarter")
        |> Fude.annotate(:band, x: {~D[2026-03-01], ~D[2026-05-01]}, text: "Launch")
        |> Fude.annotate(:line, y: 100)

      assert Export.to_markdown(chart) =~
               "- Best quarter (North, 120)\n- Launch (2026-03-01 to 2026-05-01)\n\nDraft."
    end

    test "writes times by their day" do
      chart =
        Fude.line([%{day: ~D[2026-03-01], n: 3}, %{day: ~D[2026-03-02], n: 5}], x: :day, y: :n)

      assert Export.to_markdown(chart) == """
             | Day | N |
             | --- | ---: |
             | 2026-03-01 | 3 |
             | 2026-03-02 | 5 |
             """
    end

    test "takes a spec with its data" do
      spec = Fude.Spec.dump(Fude.bar(x: :region, y: :revenue, title: "Revenue"))

      assert Export.to_markdown(spec, @sales) =~ "**Revenue**\n\n| Region | Revenue |"
      assert Export.to_markdown(spec, %{"data" => @sales}) =~ "| North | 120 |"
    end

    test "writes small multiples as one table, with a column of their panels" do
      chart = Fude.bar(@sales, x: :region, y: :revenue) |> Fude.facet(:channel)

      assert Export.to_markdown(chart) == """
             | Channel | Region | Revenue |
             | --- | --- | ---: |
             | Online | North | 120 |
             | Retail | South | 90.5 |
             """
    end

    test "writes a single number with its label and what it is measured against" do
      assert Export.to_markdown(Fude.number([%{mrr: 1200}], value: :mrr, label: "MRR")) ==
               "**MRR**: 1200\n"

      assert Export.to_markdown(Fude.trend([%{mrr: 120}, %{mrr: 100}], value: :mrr)) ==
               "**Mrr**: 120 (+20.0% from 100)\n"

      assert Export.to_markdown(Fude.progress([%{done: 62}], value: :done, goal: 80)) ==
               "**Done**: 62 of 80 (78%)\n"

      assert Export.to_markdown(Fude.gauge([%{cpu: 62}], value: :cpu, target: 80)) ==
               "**Cpu**: 62 (from 0 to 100, target 80)\n"
    end

    test "writes why a chart does not draw, and does not raise" do
      chart = Fude.bar(@sales, x: :nope, y: :revenue, title: "Broken")

      assert Export.to_markdown(chart) == """
             **Broken**

             *x: the field "nope" is not in the data*
             """

      assert Export.to_markdown(%{"title" => "Bad"}) =~
               ~r/\A\*\*Bad\*\*\n\n\*The chart's spec is not valid: /
    end
  end

  describe "to_text/2" do
    test "writes the words on their lines and the data by tabs" do
      assert Export.to_text(revenue()) == """
             Revenue

             By region

             Region\tRevenue\tChannel
             North\t120\tOnline
             South\t90.5\tRetail

             Draft. Source: Ledger
             """
    end

    test "writes a single number" do
      assert Export.to_text(Fude.number([%{mrr: 1200}], value: :mrr, label: "MRR")) ==
               "MRR: 1200\n"
    end
  end

  describe "to_html/2" do
    test "writes a figure with the words and a table, escaped" do
      chart =
        Fude.bar([%{region: "<b>North</b>", revenue: 1}],
          x: :region,
          y: :revenue,
          title: "R&D",
          source: "Ledger"
        )

      html = chart |> Export.to_html() |> Phoenix.HTML.safe_to_string()

      assert html ==
               ~s(<figure class="fude-static" data-kind="bar">) <>
                 ~s(<figcaption class="fude-head"><span class="fude-title">R&amp;D</span></figcaption>) <>
                 ~s(<table><thead><tr><th scope="col">Region</th><th scope="col">Revenue</th></tr></thead>) <>
                 ~s(<tbody><tr><td>&lt;b&gt;North&lt;/b&gt;</td><td>1</td></tr></tbody></table>) <>
                 ~s(<p class="fude-foot"><span class="fude-static-source">Source: Ledger</span></p>) <>
                 "</figure>"
    end

    test "writes a single number and an error" do
      number = Fude.number([%{mrr: 1200}], value: :mrr, label: "MRR")

      assert Phoenix.HTML.safe_to_string(Export.to_html(number)) =~
               ~s(<p class="fude-static-single"><span class="fude-label">MRR</span>: <data value="1200">1200</data></p>)

      broken = Fude.bar(@sales, x: :nope, y: :revenue)

      assert Phoenix.HTML.safe_to_string(Export.to_html(broken)) =~
               ~s(<p class="fude-error">x: the field &quot;nope&quot; is not in the data</p>)
    end
  end

  test "render/3 writes each format, as a Kotoba embed asks" do
    assert Export.render(revenue(), :markdown) == Export.to_markdown(revenue())
    assert Export.render(revenue(), :text) == Export.to_text(revenue())
    assert Export.render(revenue(), :html) == Export.to_html(revenue())

    spec = Fude.Spec.dump(Fude.bar(x: :region, y: :revenue))
    assert Export.render(spec, :markdown, @sales) =~ "| South | 90.5 |"
  end
end
