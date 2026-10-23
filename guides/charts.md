# Charts

Each kind is a function of `Fude` that takes the data and a keyword list
of channels, options and the chart's words, and gives a `Fude.Chart`:

```elixir
Fude.bar(sales, x: :region, y: :revenue, color: :channel, title: "Revenue")
```

Without data, a function gives a layer, for `Fude.layers/3`, or a chart
whose data comes later (`<.chart chart={...} data={...}>`).

## Channels

A channel says what a field of the data shows, and how (see
`Fude.Channel`):

| | |
| --- | --- |
| `:revenue` | the field as it is |
| `{:sum, :revenue}` | aggregated: `:count`, `:sum`, `:mean`, `:median`, `:min`, `:max`, `:distinct` |
| `{:month, :placed_on}` | a unit of a time: `:year`, `:quarter`, `:month`, `:week` (from Monday), `:day`, `:hour`, `:minute` |
| `{:bin, :total}` | numbers in round bins |
| `1000` | a constant, as the height of a rule |
| `[field: :revenue, aggregate: :sum, format: {:currency, "EUR"}, title: "Revenue"]` | the full form |

The full form also takes `type` (`:number`, `:time`, `:category`,
`:ordinal`), `sort` (`:ascending`, `:descending`, `:"-y"` by the other
channel, or a list of the categories in order), `format` (`:number`,
`:integer`, `:percent`, `:compact`, `{:currency, code}`, `:bytes`,
`:duration`), `scale` (`type: :log`, `domain: [0, 100]`, `zero: true`,
`nice: false`), `stack` (`:zero`, `:normalize`, `:center`, `false`) and
`axis` (`:right`, for a `y` on an axis of its own, see Layers).

A field's type is learned from its values: numbers, times (a `Date`,
`NaiveDateTime` or `DateTime`) or categories. Its title is its name in
words (`placed_on` is "Placed on"), unless the channel has one.

## The kinds

| Kind | Channels | Options |
| --- | --- | --- |
| `bar` | `x`, `y`, `color`, `tooltip` | `horizontal`, `labels` |
| `line` | `x`, `y`, `color`, `tooltip` | `curve` (`:linear`, `:monotone`, `:step`), `points` |
| `area` | `x`, `y`, `color`, `tooltip` | `curve` |
| `scatter` | `x`, `y`, `color`, `size`, `tooltip` | |
| `bubble` | `x`, `y`, `size`, `color` | |
| `pie`, `donut` | `value`, `color` | `inner` (the donut's hole) |
| `histogram` | `x`, `color` | `bins` |
| `heatmap` | `x`, `y`, `color` | |
| `waterfall` | `x`, `y` | `start` (a first total), `total` (the name of the end) |
| `funnel` | `x` (the stages), `y` | |
| `sparkline` | `x`, `y` | `curve` |
| `choropleth` | `region`, `color` | `map` |
| `bubble_map` | `region`, `size`, `color` | `map` |
| `rule` | `x` or `y` | `label`, `dashed` |
| `text` | `x`, `y`, `text` | |
| `number` | `value` | `label`, `align` |
| `trend` | `value`, `compare` | `label`, `align` |
| `gauge` | `value` | `label`, `min`, `max`, `target`, `align` |
| `progress` | `value` | `label`, `goal`, `align` |

Bars, areas, heatmaps, pies, waterfalls, funnels and maps sum the values
of the rows of the same category (and color), so that a bar is one bar.
Bars and areas with a color stack; `stack: false` on `y` sets the bars
side by side, and `stack: :normalize` to 100%.

The single numbers (`number`, `trend`, `gauge`, `progress`) are written
by the server, with no JavaScript; the browser writes the number in the
chart's locale.

A single number fills its box, as a tile of a dashboard: it is centered,
and the number, the gauge's arc and the progress bar grow with the box.
The box is the chart's `height` when it has one, or the rest of a figure
that is given a height (a card), or `--fude-single-min-height` (8rem, 11rem
for a gauge). `align: :start` sets it at the start at a fixed size, for a
number inline in a page or a table:

```elixir
Fude.trend(kpis, value: :mrr, compare: :last, label: "vs last month")
Fude.number(kpis, value: :orders, label: "Orders", align: :start)
```

A trend's change is a pill, green up and red down (`--fude-up`,
`--fude-down`); a progress has its label and its share of the goal above
the bar, as thick as `--fude-progress-height` sets it, or as the box
allows.

## Layers

Charts drawn over each other share their scales:

```elixir
Fude.layers(visits, [
  Fude.area(x: :day, y: :visits),
  Fude.line(x: :day, y: :visits),
  Fude.rule(y: 4000, label: "Goal")
], title: "Visits reach the goal")
```

Two measures of other units go on two axes: a `y` with `axis: :right`
has a scale of its own, on the right of the plot. Without a color, each
axis's layers have their color, and its title too:

```elixir
Fude.layers(months, [
  Fude.bar(x: :month, y: :orders),
  Fude.line(x: :month, y: [field: :revenue, format: {:currency, "EUR"}, axis: :right])
], title: "Revenue grows faster than orders")
```

## The words of a chart

Every function takes `:title`, `:subtitle`, `:caption`, `:source`,
`:description` (what a screen reader says; Fude writes one when it is not
given) and `:height`. See [Telling the story](story.md).

## When a chart cannot draw

A field that is not in the data, or a spec that is not valid, does not
raise: the chart says why in place of its plot, with a suggestion:

> x: the field "regoin" is not in the data; did you mean "region"?
