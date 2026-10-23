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
`:duration`), `digits` (the decimals of a `:number`, `:compact`,
`:percent` or currency, from 0 to 20), `scheme` and `mid` (the colors of
a `color` channel, see Colors), `scale` (`type: :log`, `domain: [0, 100]`, `zero: true`,
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
| `bubble` | `x`, `y`, `size`, `color`, `tooltip` | |
| `pie`, `donut` | `value`, `color`, `tooltip` | `inner` (the donut's hole) |
| `histogram` | `x`, `color`, `tooltip` | `bins` |
| `heatmap` | `x`, `y`, `color`, `tooltip` | |
| `waterfall` | `x`, `y`, `tooltip` | `start` (a first total), `total` (the name of the end) |
| `funnel` | `x` (the stages), `y`, `color`, `tooltip` | `step`, `labels` (`:outside`, `:inside`, `false`) |
| `sparkline` | `x`, `y` | `curve`, `area`, `points` (`:last`, `:extremes`), `value` |
| `choropleth` | `region`, `color`, `tooltip` | `map` |
| `bubble_map` | `region`, `size`, `color`, `tooltip` | `map` |
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
chart's locale. With no `format`, a single number is exact under 100,000
(`84,213.5`) and compact from there (`6.9M`), as a headline. A format
says which, and `digits` how many decimals:

```elixir
Fude.number(sales, value: [field: :revenue, format: :number, digits: 0])      # 6,893,914
Fude.number(sales, value: [field: :revenue, format: :compact, digits: 2])     # 6.89M
Fude.number(sales, value: [field: :revenue, format: {:currency, "EUR"}, digits: 2]) # €6,893,913.60
```

`:number` with no digits keeps a value's decimals, up to 2. A trend's
change takes the digits of its value, or one.

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

## Tooltips

A tooltip shows the values of a mark's channels, then the fields of its
`tooltip` channel, each in its format:

```elixir
Fude.bar(sales, x: :region, y: :revenue, tooltip: [:orders, [field: :margin, format: :percent], :manager])
```

Where marks are their rows (lines, points), a field is the row's value.
Where a mark is a group of rows (a bar, an area, a cell, a slice, a
region sums them), a field takes its own aggregate when it has one
(`{:max, :orders}`), else the sum of its numbers, else its first value.
On a crosshair, each series has its fields, named by it.

## Colors

A `color` channel takes its colors from a `scheme`, by name, each in
light and dark, and each readable with the common color vision
deficiencies:

| Scheme | Is |
| --- | --- |
| `:blue` (the default), `:green`, `:orange`, `:purple`, `:gray` | a ramp of one hue, light to dark |
| `:viridis` | a ramp of many hues, dark to light |
| `:red_blue`, `:red_green` | diverging: through a neutral at `mid` (0 unless given) |
| `:categorical` (the default), `:okabe_ito` | a color for each category |

```elixir
Fude.heatmap(margins, x: :quarter, y: :region, color: [field: :change, scheme: :red_green])
Fude.heatmap(temps, x: :month, y: :city, color: [field: :temp, scheme: :red_blue, mid: 15])
Fude.bar(tickets, x: :team, y: :count, color: [field: :status, scheme: ["#1baf7a", "#eda100", "#e34948"]])
```

A diverging scheme is as far from its neutral for the same distance on
each side. `:red_green` runs from a red-magenta, as ColorBrewer's PiYG,
which people who do not tell red from green still tell apart. A ramp on
categories spreads over them in order; a list of colors is a ramp for
numbers and a color for each category, in order: the way out for a
brand's colors, or for statuses whose colors mean something. Each named
scheme is a custom property (see [Theming](theming.md)).

## Funnels and sparklines

A funnel's `color: :stage` gives each stage its color, with no legend
(the axis names them); a color of another field colors the stages by it.
`step: true` makes each stage lighter than the one before, in one color.
`labels: :inside` writes each value and share in its bar, in the color
that reads on it, and outside the bars too narrow for them; `false`
writes none.

```elixir
Fude.funnel(signups, x: :stage, y: :people, color: :stage, labels: :inside)
Fude.sparkline(daily, x: :day, y: :visits, area: true, points: :extremes, value: true)
```

A sparkline's `area: true` fills under its line, fading to nothing;
`points: :last` marks its last value, `:extremes` its last, lowest and
highest; `value: true` writes its last value at the end of its line, in
`y`'s format. With no `height`, a sparkline fills the height of its box
(a card), and is 48 pixels high in a box with none.

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
