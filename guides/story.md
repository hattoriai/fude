# Telling the story

A chart on a page is read the way a graphics desk sets one: a title that
says what it shows, a subtitle that says how, the chart, and a line of
where the data comes from.

```elixir
Fude.line(sales, x: {:month, :placed_on}, y: {:sum, :total}, color: :channel,
  title: "Online keeps growing",
  subtitle: "Monthly revenue by channel, 2025–2026",
  source: "Ledger, October 2026"
)
```

## Labels on the marks

* A line chart of four series or fewer labels each line at its end,
  with a dot, and moves labels apart that would touch, with a leader to
  their line. The legend stays above.
* `labels: true` writes the value at the end of each bar, and by each
  point of a scatter or a bubble.
* A text layer with no `x` writes a column beside the categories of `y`,
  under its title: a ratio or a count beside each row.
* Names of categories wrap onto two lines, or stagger, before any is
  left out.

## Notes on the data

`Fude.annotate/3` writes a note at a place of the data, in its own terms
(a category's name, a date, a number):

```elixir
chart
|> Fude.annotate(:label, x: ~D[2026-03-01], y: 76_000, text: "The new shop opens")
|> Fude.annotate(:band, x: {~D[2025-11-01], ~D[2026-01-01]}, text: "Holidays")
|> Fude.annotate(:line, y: 4000, text: "Goal")
```

* `:label` - words with a line to their point, placed where they stay in
  the plot.
* `:band` - a shaded range of `x` or `y`, under the marks.
* `:line` - a dashed line across the chart, with its words.

Notes are part of the spec, a date as its text.

## Small multiples

`Fude.facet/3` draws the chart once for each value of a field, side by
side, on the same scales, with one legend:

```elixir
Fude.area(sales, x: :month, y: :revenue, color: :channel)
|> Fude.facet(:region, columns: 2)
|> Fude.title("Every region grows online")
```

Panels of four or more series are often clearer than one chart of them
all.
