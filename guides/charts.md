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
`:decimal_bytes`, `:duration`), `digits` (the decimals of a `:number`,
`:compact`, `:percent`, bytes or currency, from 0 to 20), `suffix` (words
after every value: `"×"`, `"/s"`), `scheme` and `mid` (the colors of
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
| `scatter` | `x`, `y`, `color`, `size`, `tooltip` | `connect`, `labels` |
| `bubble` | `x`, `y`, `size`, `color`, `tooltip` | `connect`, `labels` |
| `pie`, `donut` | `value`, `color`, `tooltip` | `inner` (the donut's hole) |
| `histogram` | `x`, `color`, `tooltip` | `bins` |
| `heatmap` | `x`, `y`, `color`, `tooltip` | |
| `waterfall` | `x`, `y`, `tooltip` | `start` (a first total), `total` (the name of the end) |
| `funnel` | `x` (the stages), `y`, `color`, `tooltip` | `step`, `labels` (`:outside`, `:inside`, `false`) |
| `sparkline` | `x`, `y` | `curve`, `area`, `points` (`:last`, `:extremes`), `value` |
| `choropleth` | `region`, `color`, `tooltip` | `map` |
| `bubble_map` | `region`, `size`, `color`, `tooltip` | `map` |
| `timeline` | `y` (the tasks), `x` (a start), `x2` (an end), `color`, `tooltip` | |
| `boxplot` | `x`, `y` (the numbers of each category) | `outliers` |
| `candlestick` | `x`, `open`, `high`, `low`, `close`, `tooltip` | |
| `treemap` | `name`, `value`, `color`, `tooltip` | `labels` |
| `radar` | `x` (the spokes), `y`, `color`, `tooltip` | |
| `radial_bar` | `x`, `y` | `max`, `labels` |
| `rule` | `x` or `y` | `label`, `dashed` |
| `text` | `x`, `y`, `text` (with no `x`: a column beside `y`) | |
| `number` | `value`, `spark` | `label`, `align` |
| `trend` | `value`, `compare`, `spark` | `label`, `align` |
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

A `spark` channel draws a number's history under it: the value's field by
the spark's field (a time, in its order), summed for each of its values,
or by the value's own aggregate. The line ends on its last point, the
number itself, in the first color of the series (`--fude-series-1`), as
high as `--fude-spark-height` (2rem). It needs two points; with rows
newest first, as a trend's are, the first row is the number and the last
point of its line:

```elixir
Fude.trend(months, value: :mrr, compare: :previous, spark: :month, label: "vs last month")
```

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

A tooltip can also answer the reader's next question, from data the
browser already has. Put what it adds in the same list:

```elixir
Fude.line(revenue, x: :month, y: :revenue, color: :channel, tooltip: [change: true])
Fude.bar(sales, x: :region, y: :revenue, tooltip: [:manager, rank: true, history: true])
```

| Key | Adds, under the mark's value |
| --- | --- |
| `change: true` | its change from the series' point before: "▲ 12.4% vs February 2026", green up and red down (`--fude-up`, `--fude-down`) |
| `share: true` | its share of the whole: "34% of March" for a stacked segment, "21% of total" for a bar; the default on stacked marks (`share: false` takes it off); a slice has its share already |
| `rank: true` | its rank in its series: "#2 of 14" |
| `history: true` | a small line of its series, with the hovered mark on it: the shape of a series of bars, or of a heatmap's row |

On a crosshair, each series has its change and its share; a history is
for a hovered mark. In a spec, they go at the end of the `"tooltip"`
list, as a map: `"tooltip": ["manager", {"rank": true}]`.

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

## Timelines, box plots and candlesticks

A timeline draws a bar for each task from its start to its end, on an axis
of times (or of numbers: laps, minutes). Its tooltip gives the span and
how many days it is; its table, each task with its start and its end.

```elixir
Fude.timeline(plan, y: :task, x: :start, x2: :finish, color: :team)
```

A box plot takes the rows as they are, and the server works out each
category's numbers: its quartiles and median (interpolated, as R's and
NumPy's default), its whiskers to the furthest values within 1.5 times
the box (Tukey's), and the values beyond them, drawn as points
(`outliers: false` leaves them out). The tooltip and the table give the
five numbers and the count.

```elixir
Fude.boxplot(orders, x: :region, y: [field: :days, title: "Days to deliver"])
```

A candlestick has a candle for each `x`: a body from its open to its
close, green when it closed higher and red when lower
(`--fude-increase`, `--fude-decrease`), and a wick from its low to its
high. Days are in time order; a day without its four prices is left out.

```elixir
Fude.candlestick(prices, x: :day, open: :open, high: :high, low: :low,
  close: [field: :close, format: {:currency, "EUR"}])
```

## Treemaps, radars and radial bars

A treemap's tiles are as large as their values, laid out in the browser
at the plot's size, each as near to square as it can be. A `color` keeps
its tiles together, with a legend; with none, the tiles are of one hue,
lighter as they get smaller. The tiles that have room are named, with
their values under them; the tooltip gives each tile's share.

```elixir
Fude.treemap(cities, name: :city, value: [field: :people, format: :compact], color: :country)
```

A radar has a spoke for each category of `x`, from zero at the center,
and a shape for each `color`. Radial bars draw a ring for each category,
its arc as long as its value of `max` (100 unless given, or the largest
value when it is over 100), named with its value at its start.

```elixir
Fude.radar(scores, x: :measure, y: :score, color: :product)
Fude.radial_bar(goals, x: :channel, y: [field: :done, suffix: "%"])
```

Both are harder to read than bars: a radar's shape changes with the
order of its spokes, and an outer ring looks larger than an inner ring of
the same value. Use them for a few series and few categories, with their
values written; bars compare more exactly.

## Points joined in each category

`connect: true` on a scatter or a bubble draws a line under the points of
each category, from its least value to its greatest: a dumbbell, for a
before and an after, or two of anything, on each row. The category is on
`y` (the lines across) or on `x` (the lines up); a chart of two numbers
has none to join, and says so. `labels: true` writes each point's value
by it, the least of a category below its point and the greatest above,
in the format of its axis:

```elixir
Fude.layers(runs, [
  Fude.scatter(
    x: [field: :rate, format: :decimal_bytes, suffix: "/s", scale: [type: :log]],
    y: [field: :benchmark, title: false],
    color: :parser,
    connect: true,
    labels: true
  ),
  Fude.text(y: :benchmark, text: [field: :speedup, digits: 1, suffix: "×"])
], title: "Parsing throughput", subtitle: "Higher is better")
```

The rows are long: one for each point (a benchmark and a parser), each
with its category. A text layer with a category on `y` and no `x` is a
column at the right of the plot, under its title (the text's), with the
first value of each category: the speedup beside each dumbbell, or a
count beside a bar. `labels: true` on a scatter of many points leaves out
the labels that would cover others; the tooltip has every value.

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

## A chart's height

A plot is 320 pixels high, or the chart's `height`. `<.chart height={:fill}>`
takes the height its box gives it, as a dashboard's card does, and draws
again when the box changes height (a card resized), as it does when it
changes width. It is at least 120 pixels high. A single value fills its
box in the same way.

```heex
<div class="card" style="height: 24rem">
  <.chart id="revenue" chart={@chart} height={:fill} table={:swap} />
</div>
```

## The data as a table

Each chart has its data as a table, as it draws it (summed, in bins).
`table` says where:

* `true` (or `:below`), the default: under the chart, behind a **Data**
  toggle that opens below it.
* `:swap`: in the chart's place, at its size, behind a **Data** button;
  the table scrolls in the plot's box, and its header stays. For a box of
  a fixed size, as a dashboard's card, which the table would otherwise
  stretch.
* `false`: none.

```heex
<.chart id="revenue" chart={@chart} table={:swap} />
```

Open or shown is the reader's: a render of the LiveView (new data, or the
page around the chart) leaves it as they left it.

## Motion

A chart's marks move to their new places when its data changes (see
[Live](live.md)). `animate` sets it for a chart: `true` (the default, for
as long as `--fude-duration`), `false` (no motion, on the first draw or
after), or `[duration: 800]`, in milliseconds. `<.chart animate={false}>`
sets it for one page, over the chart's. A reader who asks for reduced
motion has none, whatever the chart says.

## When a chart cannot draw

A field that is not in the data, or a spec that is not valid, does not
raise: the chart says why in place of its plot, with a suggestion:

> x: the field "regoin" is not in the data; did you mean "region"?
