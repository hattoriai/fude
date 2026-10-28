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

The data is labelled where the labels fit, with no option: `labels:
true` labels every mark that can be, `labels: false` none.

* **Lines** of four series or fewer are named at their ends, with a dot,
  moved apart where they would touch, with a leader to their line. A
  click on a name hides its line, or shows it again; `labels: true` adds
  each line's last value to its name, and a line of no series is labelled
  by its last value.
* **Bars** have their values at their ends, all of them or none; compact
  ("€210K") where the full values do not fit. A **stack** has its total
  at its end, and each segment's value inside it where it fits, in the
  color that reads on it; `labels: :series` writes the series' name in
  each segment instead ("Social", "Alliance"). A **stack of 100%** has
  each segment's share inside it, and no totals. Bars colored by their own
  categories (`color: :party` on `x: :party`) are bars, not stacks: each
  has its value once, and no legend repeats the axis. **Horizontal bars**
  with their values leave out their value axis. Bars under a line (two
  measures) are labelled only when asked.
* **Pies and donuts** name each slice with its share, inside it where
  they fit, else outside with a short line; a donut has its total in its
  hole.
* **Heatmaps** have each cell's value, in the color that reads on it: all
  of them, compact if need be, or none.
* **Points** of a scatter or a bubble have their values with `labels:
  true`.
* A text layer with no `x` writes a column beside the categories of `y`,
  under its title: a ratio or a count beside each row. Several columns
  stand side by side, in the order of their layers; `change: true`
  writes a column of changes with their signs, "+25" in `--fude-up` and
  "−36" in `--fude-down`, "–" for none.
* Names of categories wrap onto two lines, or stagger, before any is
  left out.
* With no format, labels are compact from 100,000, as single values are.

## Legends

A legend is there when labels cannot name the series. Where they do
(lines named at their ends, a pie of six slices or fewer with its
labels), the legend is out of sight, and still the keyboard's way to hide
a series: it shows when it has the focus. A legend reads in the order of
the marks: a vertical stack from its top segment down, lines from the
highest at their end.

## One series against the rest

`highlight` on a color names the series that matter; they keep their
colors and are drawn over the others, in gray (`--fude-context`), and
their names are bold:

```elixir
Fude.line(sales, x: :month, y: :revenue, color: [field: :channel, highlight: "Online"])
```

A list highlights several. A line chart of more than five series reads
better as small multiples, or with a highlight; the browser's console
says so.

## Units

A value axis writes its unit on its top tick only, as a graphics desk
does: "€400K", then "300K", "200K". A currency, a percent and a
`suffix` are units; bytes and durations keep theirs on every tick, as
they change from one to the next. Labels and tooltips always have them.

## Notes on the data

`Fude.annotate/3` writes a note at a place of the data, in its own terms
(a category's name, a date, a number):

```elixir
chart
|> Fude.annotate(:label, x: ~D[2026-03-01], y: 76_000, text: "The new shop opens")
|> Fude.annotate(:band, x: {~D[2025-11-01], ~D[2026-01-01]}, text: "Holidays")
|> Fude.annotate(:line, y: 4000, text: "Goal")
```

* `:label` - a callout: a ringed dot on its point, a short line, and its
  words, the first line bold, where they cover the least of the data
  (above or below it, right or left, near or farther), in the plot.
* `:band` - a shaded range of `x` or `y`, under the marks, its words at
  its top.
* `:line` - a dashed line across the chart, its words at its start or
  its end, where they cover the least of the data. A rule's label too.
  With an `x` and a category of `y` (or the other way round), it crosses
  that category's band only: `x: 116 / 230, y: "Seats"` marks the
  majority on the bar of seats, not on the bar of votes.

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
