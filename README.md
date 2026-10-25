# Fude

![Fude — Charts for Phoenix](https://raw.githubusercontent.com/hattoriai/fude/main/media/banner.png)

Fude (筆, the brush) is charts for Phoenix. Sumi is the ink; Fude draws
with it. It gives your app:

* charts for LiveView from one line of Elixir:
  `Fude.bar(sales, x: :region, y: :revenue)`, and the full grammar
  (channels, aggregates, units of time, bins, layers) when you need it;
* charts that look edited, not generated: titles, subtitles and sources
  as a graphics desk sets them, labels at the ends of lines, hairline
  grids, rounded bar ends, notes on the data (`Fude.annotate/3`), small
  multiples (`Fude.facet/3`), and the Sumi theme;
* bars, lines, areas, points, bubbles, pies, donuts, histograms,
  heatmaps, waterfalls, funnels, sparklines, region maps of the world
  and the US states, and single numbers (a number, a trend, a gauge, a
  progress bar);
* charts that move: when the data changes, each mark goes from where it
  was to where it is; new points stream in with `Fude.Live.append/5`
  without sending the data again;
* your data as you have it: a list of maps, a query result, or an Ecto
  query that the database groups and aggregates (`Fude.query/3`), so a
  chart of fifty million rows reads a few hundred;
* a chart as plain data: `Fude.Spec.dump/1` gives a map with a version
  to save in a column or a file, and `Fude.Spec.load/1` takes it back,
  with every error where it is and what to write instead;
* tooltips with every series at the pointer, a legend that highlights,
  the keyboard (the arrows move through the data, a screen reader says
  each value), and a table of the data under each chart;
* SVG and PNG files of a chart, from the same drawing as the screen;
* a chart outside the browser, as Markdown, plain text or HTML written on
  the server (`Fude.to_markdown/2`, `Fude.Export`): its words and its data
  as a table, for a document's copy, an email, or an agent that reads the
  page;
* collaboration on a chart, with [Issho](https://hex.pm/packages/issho)
  (`Fude.Issho`): a chart's spec as a room's shared state, the others'
  pointers on its marks, and tools for agents that change it as people
  do;
* `Fude.Test`, to read what a chart shows in `Phoenix.LiveViewTest`
  with no browser.

The charts are a prebuilt JavaScript bundle in the Hex package, 14 KB
gzipped. Your app does not run Node.js for it: you add the hook and one
style sheet.

## What the charts do

| | |
| --- | --- |
| Kinds | `bar` (and `horizontal: true`), `line`, `area`, `scatter`, `bubble`, `pie`, `donut`, `histogram`, `heatmap`, `waterfall`, `funnel`, `sparkline`, `choropleth`, `bubble_map`, `rule`, `text`, `number`, `trend`, `gauge`, `progress`; `Fude.layers/3` for several over each other |
| Channels | `x`, `y`, `color`, `size`, `value`, `region`, `tooltip`: a field, `{:sum, :revenue}`, `{:month, :created_at}`, `{:bin, :total}`, or the full form with a type, a sort, a format, a title, a scale and a stack |
| Data | lists of maps (atom or string keys), `%{columns, rows}` as a query result has them, and Ecto queries grouped in PostgreSQL, MySQL or SQLite; decimals, dates and times as they are; only the fields a chart draws are read |
| Looks | titles, subtitles, captions and sources; labels at line ends with leaders when they would touch; value labels; category names that wrap or stagger before they thin; a validated color order for every series, in light and dark |
| Notes | labels with a line to their point, bands of a range, lines with words: `Fude.annotate(chart, :label, x: ~D[2026-03-01], y: 76_000, text: "The new shop opens")` |
| Small multiples | `Fude.facet(chart, :region, columns: 3)`: a panel for each value, on shared scales, with one legend |
| Maps | the world's countries (Natural Earth, Equal Earth) and the US states (Albers USA), by ISO code, number code, postal code or name; loaded only by the pages that draw them |
| Live | charts follow their assigns and move; `Fude.Live.append/5` streams rows into a window of the last `max` |
| Specs | `Fude.Spec.dump/1` and `load/1`: JSON with a version, migrated forward; errors with their path and a suggestion (`did you mean "sum"?`) |
| Interaction | a crosshair and one tooltip for every series on lines and areas, a tooltip on each mark of the others, a legend that highlights and hides, keyboard navigation with announcements |
| Collaboration | `Fude.Issho`: a chart as an Issho room's shared state, changed by people with `Fude`'s functions and by agents with `read_chart` and `change_chart`, always valid; the others' pointers on its marks |
| Export | `<.chart export>` buttons and `Fude.Live.export/3`: SVG, and PNG at twice the size; `Fude.Export` on the server: Markdown, text and HTML of the chart's words and data, with no browser |
| Locales | numbers, currencies and dates in the chart's locale, with the browser's `Intl` |
| Theming | CSS custom properties, the Sumi theme, dark mode, reduced motion, forced colors |
| Accessibility | a description for screen readers, keyboard navigation through the data, live announcements, a table of the data, contrast-checked colors |

## Performance

Measured with `mix run bench/compile.exs`: the time the server takes to
make a chart of rows in memory, on 200,000 rows.

| | |
| --- | --- |
| Bars, summed by category and color | 0.16 s |
| A line by month | 0.18 s |
| A histogram of 40 bins | 0.23 s |
| A scatter of every row | 0.21 s |

* An Ecto query does its grouping in the database: the server reads the
  groups, not the rows.
* The browser draws the marks on a canvas and its words as SVG; it draws
  again only what moves, at 60 frames a second.

## Install

Fude needs Elixir 1.18 or later (it uses the built-in `JSON` module),
Phoenix 1.7.14 or 1.8, and Phoenix LiveView 1.1 or later. A chart of an
Ecto query needs Ecto 3.13 or later.

Add `fude` to the deps in `mix.exs`:

```elixir
def deps do
  [
    {:fude, "~> 0.8"}
  ]
end
```

Then run:

```sh
mix deps.get
mix fude.install
```

The installer adds the hook to `assets/js/app.js` and the style sheet to
`assets/css/app.css`, and prints what it changed. Give `--dry-run` to see
the changes first. It does not add what a file already has, so you can
run it again.

### The manual steps

To make the same changes by hand, import the hook in `assets/js/app.js`
and add it to the hooks of the `LiveSocket`:

```js
import { Fude } from "fude"

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Fude},
})
```

Import the style sheet in `assets/css/app.css` (and the Sumi theme, if you
want it: Sumi is the design system of Hattori AI, the makers of Fude,
Masu, Kotoba, Koyomi and Jumon). Put these lines below the other `@import`
lines of `app.css`:

```css
@import "../../deps/fude/priv/static/fude.css";
/* @import "../../deps/fude/priv/static/fude-sumi.css"; */
```

For map charts, register the maps the app draws (see the
[Maps](guides/maps.md) guide):

```js
import { registerMap } from "fude"
import world from "fude/maps/world.json"

registerMap("world", world)
```

### `NODE_PATH=deps`

`import { Fude } from "fude"` resolves through the `NODE_PATH` of your
esbuild profile, which must have `deps/`. The Phoenix generators already
set it. If your profile has no `NODE_PATH`, add it in `config/config.exs`:

```elixir
env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
```

## Use

```heex
<.chart
  id="revenue"
  chart={
    Fude.line(@sales, x: {:month, :placed_on}, y: {:sum, :total}, color: :channel)
    |> Fude.title("Online keeps growing", subtitle: "Monthly revenue by channel")
  }
/>
```

Import the components in the `html_helpers` of your web module:

```elixir
import Fude.Components
```

A chart of an Ecto query, grouped in the database:

```elixir
Order
|> where(shop_id: ^shop.id)
|> Fude.query(Repo)
|> Fude.bar(x: :status, y: {:count, :id})
```

A chart saved as data, and drawn again with its data:

```elixir
spec = Fude.Spec.dump(chart)
# later
<.chart id="revenue" spec={report.chart} data={@sales} />
```

When `@sales` changes, the chart draws again in place: its marks move
from where they were.

## Guides

* [Quickstart](guides/quickstart.md) - a first chart, step by step.
* [Charts](guides/charts.md) - the kinds, their channels and options, layers.
* [Data](guides/data.md) - lists, query results, Ecto queries in the database, Masu's grids.
* [Telling the story](guides/story.md) - words, notes on the data, small multiples.
* [Maps](guides/maps.md) - regions colored by a value, circles on a map.
* [Specs](guides/specs.md) - a chart as data: saving, loading, versions, errors.
* [Live](guides/live.md) - charts that follow their data, streamed points, export.
* [Collaboration](guides/collaboration.md) - shared charts with Issho, for people and agents.
* [Testing](guides/testing.md) - `Fude.Test` in `Phoenix.LiveViewTest`.
* [Theming](guides/theming.md) - the custom properties, dark mode, the Sumi theme.
* [Accessibility](guides/accessibility.md) - what a person who does not see the chart gets.
* [Known limits](guides/limits.md) - what Fude does not do yet.

## Development

```sh
mix deps.get
mix fude.build   # the bundle and the style sheets, into priv/static
mix dev          # the gallery at http://localhost:4099
```

### Tests

```sh
mix test                        # Elixir, with SQLite for the queries
FUDE_DB=postgres mix test       # the queries on PostgreSQL
FUDE_DB=mysql mix test          # and on MySQL
mix test --include build        # the build and the package
mix test.js                     # the browser's rules, maps and merges
```

The rules that both the server and the browser apply (ticks, nice
domains, bins, units of time) are tested on both sides with one fixture,
`test/fixtures/rules.json`.

### Release

`mix release` builds the bundle, checks `priv/static` and the version of
`package.json`, publishes to Hex and tags the version.

## Contributing

See [CONTRIBUTING.md](https://github.com/hattoriai/fude/blob/main/CONTRIBUTING.md): when a change needs an issue
first, and what a pull request needs.

## License

Fude is released under the MIT License. See `LICENSE`. The maps are made
from Natural Earth and the U.S. Census Bureau (public domain), through
world-atlas and us-atlas (ISC) and i18n-iso-countries (MIT). See `NOTICE`.
