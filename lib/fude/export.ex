defmodule Fude.Export do
  @moduledoc """
  A chart outside the browser: as Markdown, plain text or HTML, written on
  the server from the chart and its data, with no hook and no JavaScript.

  A document that embeds a chart, its copy as Markdown, an email, a search
  index, an agent that reads the page: none of them runs the hook, so
  each gets the chart's words (title, subtitle, caption, source, notes)
  and the data it draws, as the page's table of the data has it.

      chart = Fude.bar(sales, x: :region, y: :revenue, title: "Revenue", source: "Ledger")

      Fude.Export.to_markdown(chart)
      #=> \"\"\"
      **Revenue**

      | Region | Revenue |
      | --- | ---: |
      | North | 120 |
      | South | 90 |

      Source: Ledger
      \"\"\"

  Each function takes a chart (from the functions of `Fude`), or a spec
  (from `Fude.Spec.dump/1`), with its data as `<.chart>` takes it: the
  chart's own, or a map of names for a chart of several. A single number
  (`Fude.number/2`, `trend`, `progress`, `gauge`) is its label and its
  value; small multiples are one table, with a column of their panels.

  Numbers and dates are written plainly (`1234.5`, `2026-03-01`), as the
  table is before the browser writes them in a locale. The table has the
  page's first thousand rows.

  A chart that cannot draw (a field that is not in the data, a spec that
  is not valid) is its title and why, and does not raise.

  ## In a document

  [Kotoba](https://hex.pm/packages/kotoba) renders an embed as Markdown,
  text and HTML with a function of the embed and the format, and
  `render/3` takes the format as Kotoba gives it:

      def render(%{kind: "chart", ref: id}, format) do
        report = Reports.get!(id)
        Fude.Export.render(report.chart, format, report.rows)
      end

      def render(_embed, _format), do: nil

  A page copied as Markdown then has the chart's table in the chart's
  place, and an agent that reads the page reads its numbers. An embed's
  ref is the person's input: load the chart as its own page does, with
  the reader's permission.
  """

  alias Fude.{Annotation, Chart, Compile, Spec}
  alias Phoenix.HTML.Engine

  @typedoc "A chart, or a spec of one (`Fude.Spec.dump/1`)."
  @type chart :: Chart.t() | map()

  @typedoc "What `render/3` writes."
  @type format :: :markdown | :text | :html

  @doc """
  The chart in a format: `to_markdown/2` for `:markdown`, `to_text/2` for
  `:text`, `to_html/2` for `:html`.
  """
  @spec render(chart(), format(), term()) :: String.t() | Phoenix.HTML.safe()
  def render(chart, format, data \\ nil)
  def render(chart, :markdown, data), do: to_markdown(chart, data)
  def render(chart, :text, data), do: to_text(chart, data)
  def render(chart, :html, data), do: to_html(chart, data)

  @doc """
  The chart as Markdown: its title in bold, its subtitle in italics, its
  data as a table (numbers aligned right), its notes as a list, then its
  caption and source.
  """
  @spec to_markdown(chart(), term()) :: String.t()
  def to_markdown(chart, data \\ nil) do
    chart
    |> read(data)
    |> blocks(&md/1)
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
  end

  @doc """
  The chart as plain text: its words on lines of their own, and its data
  as lines of values by tabs, under a line of the columns' titles, which a
  spreadsheet takes as it is pasted.
  """
  @spec to_text(chart(), term()) :: String.t()
  def to_text(chart, data \\ nil) do
    chart
    |> read(data)
    |> blocks(&text/1)
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
  end

  @doc """
  The chart as HTML for a page with no LiveView (an email, a document's
  cached HTML): a `figure.fude-static` with the chart's words, in the
  classes of `<.chart>` (`fude-head`, `fude-title`, `fude-foot`...), and
  its data as a table. It reads with no style sheet, as in an email.
  """
  @spec to_html(chart(), term()) :: Phoenix.HTML.safe()
  def to_html(chart, data \\ nil) do
    %{wire: wire} = read = read(chart, data)

    {:safe,
     [
       ~s(<figure class="fude-static" data-kind="),
       escape(wire["kind"] || "chart"),
       ~s(">),
       html_head(wire),
       html_body(read),
       html_notes(read.notes),
       html_foot(wire),
       "</figure>"
     ]}
  end

  # -- What the chart says -----------------------------------------------------

  # The chart compiled as <.chart> compiles it: its words, and its single
  # value, its table, or why it does not draw.
  defp read(%Chart{} = chart, data) do
    case Compile.compile(chart, Compile.datasets(chart, data)) do
      {:ok, wire} -> result(chart, wire, [])
      {:error, errors} -> result(chart, words(chart), errors)
    end
  end

  defp read(spec, data) when is_map(spec) do
    case Spec.load(spec) do
      {:ok, chart} ->
        read(chart, data)

      {:error, errors} ->
        result(nil, %{"title" => spec["title"] || spec[:title]}, [
          "The chart's spec is not valid: " <> String.trim(Spec.format_errors(errors))
        ])
    end
  end

  defp read(other, _data) do
    raise ArgumentError, "Fude.Export takes a chart or a spec, got: #{inspect(other)}"
  end

  defp words(%Chart{} = chart) do
    %{
      "kind" => Atom.to_string(Chart.kind(chart) || :chart),
      "title" => chart.title,
      "subtitle" => chart.subtitle,
      "caption" => chart.caption,
      "source" => chart.source
    }
  end

  defp result(chart, wire, errors) do
    {heads, rows} = if errors == [], do: Compile.table(wire), else: {[], []}

    %{
      wire: wire,
      errors: errors,
      heads: heads,
      rows: rows,
      notes: if(chart && errors == [], do: notes(chart.annotations), else: [])
    }
  end

  # The notes on the data that have words, each with where it is.
  defp notes(annotations) do
    for %Annotation{text: text} = note <- annotations, text not in [nil, ""] do
      case place(note) do
        nil -> text
        place -> "#{text} (#{place})"
      end
    end
  end

  defp place(%Annotation{x: x, y: y}) do
    [x, y]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(", ", fn
      {from, to} -> "#{plain(from)} to #{plain(to)}"
      value -> plain(value)
    end)
    |> case do
      "" -> nil
      place -> place
    end
  end

  # The parts of the chart in order, each written by `write`: a function of
  # {:title | :subtitle | :error | :single | :table | :empty | :notes |
  # :foot, value}, which gives nil to leave a part out.
  defp blocks(%{wire: wire} = read, write) do
    [
      {:title, wire["title"]},
      {:subtitle, wire["subtitle"]},
      body(read),
      {:notes, read.notes},
      {:foot, foot(wire)}
    ]
    |> Enum.reject(fn {_part, value} -> value in [nil, "", []] end)
    |> Enum.map(write)
    |> Enum.reject(&is_nil/1)
  end

  defp body(%{errors: [_ | _] = errors}), do: {:error, Enum.join(errors, ". ")}
  defp body(%{wire: %{"single" => single}}), do: {:single, single}
  defp body(%{rows: []}), do: {:empty, "No data."}
  defp body(%{heads: heads, rows: rows}), do: {:table, {heads, rows}}

  defp foot(wire) do
    [wire["caption"], wire["source"] && "Source: " <> wire["source"]]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " ")
    end
  end

  # A single number in words: its label, its value, and what it is measured
  # against (a trend's change, a progress's goal, a gauge's scale).
  defp single_words(single) do
    value = plain(single["value"]) || "—"

    {single["label"], value <> against(single)}
  end

  defp against(%{"value" => value, "compare" => compare})
       when is_number(value) and is_number(compare) and compare != 0 do
    change = (value - compare) / abs(compare) * 100
    sign = if change >= 0, do: "+", else: ""
    " (#{sign}#{:erlang.float_to_binary(change, decimals: 1)}% from #{plain(compare)})"
  end

  defp against(%{"value" => value, "goal" => goal})
       when is_number(value) and is_number(goal) and goal > 0,
       do: " of #{plain(goal)} (#{round(value / goal * 100)}%)"

  defp against(%{"min" => min, "max" => max} = single) when is_number(min) and is_number(max) do
    target = if is_number(single["target"]), do: ", target #{plain(single["target"])}", else: ""
    " (from #{plain(min)} to #{plain(max)}#{target})"
  end

  defp against(_single), do: ""

  # -- Markdown ----------------------------------------------------------------

  defp md({:title, title}), do: "**#{md_escape(title)}**"
  defp md({:subtitle, subtitle}), do: "*#{md_escape(subtitle)}*"
  defp md({:error, error}), do: "*#{md_escape(error)}*"
  defp md({:empty, words}), do: "*#{words}*"
  defp md({:foot, foot}), do: md_escape(foot)
  defp md({:notes, notes}), do: Enum.map_join(notes, "\n", &("- " <> md_escape(&1)))

  defp md({:single, single}) do
    case single_words(single) do
      {nil, value} -> md_escape(value)
      {label, value} -> "**#{md_escape(label)}**: #{md_escape(value)}"
    end
  end

  defp md({:table, {heads, rows}}) do
    rules =
      heads
      |> Enum.with_index()
      |> Enum.map(fn {_head, i} -> if numbers?(rows, i), do: "---:", else: "---" end)

    [heads, rules | Enum.map(rows, fn row -> Enum.map(row, &cell/1) end)]
    |> Enum.with_index()
    |> Enum.map_join("\n", fn
      {rules, 1} -> "| " <> Enum.join(rules, " | ") <> " |"
      {cells, _i} -> "| " <> Enum.map_join(cells, " | ", &md_cell/1) <> " |"
    end)
  end

  # A column of numbers: each value a number, or none.
  defp numbers?(rows, i) do
    values = rows |> Enum.map(&Enum.at(&1, i)) |> Enum.reject(&is_nil/1)
    values != [] and Enum.all?(values, &is_number/1)
  end

  defp md_cell(value), do: value |> one_line() |> md_escape()

  # The characters Markdown reads as its own, in words, are written as they are.
  defp md_escape(text), do: String.replace(text, ~r/[\\`*_\[\]<>|#]/, "\\\\\\0")

  # -- Text --------------------------------------------------------------------

  defp text({:notes, notes}), do: Enum.map_join(notes, "\n", &("- " <> &1))

  defp text({:single, single}) do
    case single_words(single) do
      {nil, value} -> value
      {label, value} -> "#{label}: #{value}"
    end
  end

  defp text({:table, {heads, rows}}) do
    Enum.map_join(
      [heads | Enum.map(rows, fn row -> Enum.map(row, &cell/1) end)],
      "\n",
      fn cells ->
        Enum.map_join(cells, "\t", &(&1 |> one_line() |> String.replace("\t", " ")))
      end
    )
  end

  defp text({_part, words}), do: words

  # -- HTML --------------------------------------------------------------------

  defp html_head(%{"title" => title, "subtitle" => subtitle})
       when title not in [nil, ""] or subtitle not in [nil, ""] do
    [
      ~s(<figcaption class="fude-head">),
      span("fude-title", title),
      span("fude-subtitle", subtitle),
      "</figcaption>"
    ]
  end

  defp html_head(_wire), do: []

  defp html_body(%{errors: [_ | _] = errors}),
    do: [~s(<p class="fude-error">), escape(Enum.join(errors, ". ")), "</p>"]

  defp html_body(%{wire: %{"single" => single}}) do
    {label, value} = single_words(single)

    [
      ~s(<p class="fude-static-single">),
      span("fude-label", label),
      if(label, do: ": ", else: ""),
      ~s(<data value="),
      escape(plain(single["value"]) || ""),
      ~s(">),
      escape(value),
      "</data></p>"
    ]
  end

  defp html_body(%{rows: []}), do: ~s(<p class="fude-static-empty">No data.</p>)

  defp html_body(%{heads: heads, rows: rows}) do
    [
      "<table><thead><tr>",
      Enum.map(heads, &[~s(<th scope="col">), escape(&1), "</th>"]),
      "</tr></thead><tbody>",
      Enum.map(rows, fn row ->
        ["<tr>", Enum.map(row, &["<td>", escape(cell(&1)), "</td>"]), "</tr>"]
      end),
      "</tbody></table>"
    ]
  end

  defp html_notes([]), do: []

  defp html_notes(notes),
    do: [~s(<ul class="fude-notes">), Enum.map(notes, &["<li>", escape(&1), "</li>"]), "</ul>"]

  defp html_foot(wire) do
    case {present(wire["caption"]), present(wire["source"])} do
      {nil, nil} ->
        []

      {caption, source} ->
        [
          ~s(<p class="fude-foot">),
          span("fude-caption", caption),
          if(caption && source, do: " ", else: []),
          html_source(source),
          "</p>"
        ]
    end
  end

  # Its own class: the page's style sheet writes "Source: " before a .fude-source.
  defp html_source(nil), do: []

  defp html_source(source),
    do: [~s(<span class="fude-static-source">Source: ), escape(source), "</span>"]

  defp present(text) when text in [nil, ""], do: nil
  defp present(text), do: text

  defp span(_class, text) when text in [nil, ""], do: []
  defp span(class, text), do: [~s(<span class="), class, ~s(">), escape(text), "</span>"]

  defp escape(text), do: Engine.html_escape(text)

  # -- Values ------------------------------------------------------------------

  defp cell(value), do: plain(value) || ""

  defp one_line(text), do: String.replace(text, ~r/\s*\R\s*/, " ")

  defp plain(nil), do: nil
  defp plain(value) when is_float(value), do: :erlang.float_to_binary(value, [:short])
  defp plain(%Date{} = date), do: Date.to_iso8601(date)
  defp plain(%DateTime{} = time), do: DateTime.to_iso8601(time)
  defp plain(%NaiveDateTime{} = time), do: NaiveDateTime.to_iso8601(time)
  defp plain(value), do: to_string(value)
end
