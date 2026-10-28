# Changelog

All notable changes to Fude are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Fude follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Brushing (#13): `brush: :zoom` or `brush: :select` on a chart. A drag
  across the x axis (a long press, then a drag, on a phone; Shift and the
  arrows on the keyboard) chooses a range, snapped to whole units of a
  time, written as it is dragged ("Mar – May 2026"). `:zoom` zooms the
  chart in place, with a Reset zoom button, a double click and Escape to
  go back; `:select` sends the server `"fude:brush"` with the range, and
  `Fude.Live.brush_range/1` reads it as dates or numbers. The panels of
  small multiples brush together. In specs as `"brush"`. See the Live
  guide, "Brushing a range".

- Linked hover (#14): `<.chart link="months">`. Charts of the same `link`
  show the place hovered on one (or moved to with the keyboard) together:
  a crosshair with each line's value, or the bars there brought forward,
  with the tooltip only on the hovered chart. Times match within the
  coarser of the two axes' units, categories by their names. In the
  browser only. See the Live guide, "Linked hover".

- Dumbbells: `connect: true` on a scatter or a bubble joins the points of
  each category with a line under them (a before and an after, two
  parsers on a benchmark), across a category on `y` or on `x`. See the
  Charts guide, "Points joined in each category".
- `labels: true` on a scatter or a bubble writes each point's value by
  it; with `connect`, the least of a category below its point and the
  greatest above. A label that would cover another is left out.
- A text layer with a category on `y` and no `x` is a column at the right
  of the plot, under its title, beside each category: a speedup beside a
  dumbbell, a count beside bars.
- `suffix` on a channel: words after every value, on its axis, its labels
  and its tooltip (`suffix: "×"`, `suffix: "/s"`), in specs as `"suffix"`.
- The format `:decimal_bytes`: bytes in steps of 1,000, so that the ticks
  of a log scale are round (10 MB, 100 MB, 1 GB). `:bytes` takes `digits`.

### Fixed

- A text layer drew nothing in the browser.
- A log scale with a `domain` of its own widened it to whole powers of
  ten; it keeps it now, as a linear scale does, with the powers of ten
  inside it as its ticks.

## [0.8.0] - 2026-10-25

### Added

- `Fude.Export`, and `Fude.to_markdown/2`, `Fude.to_text/2` and
  `Fude.to_html/2`: a chart outside the browser, written on the server
  from the chart (or a spec) and its data. Its title, subtitle, notes,
  caption and source, and its data as the page's table has it (a single
  number as its label and value), as Markdown, as text with tabs, or as
  HTML with a table. `Fude.Export.render/3` takes the format as Kotoba's
  embeds give it, so a chart embedded in a document is its table in the
  document's Markdown and text, not only its title.

## [0.7.0] - 2026-10-24

### Added

- The Sumi theme follows Sumi's seven themes and their accents: the
  sequential ramp is the theme's accent (`--fude-sequential: accent`, a
  ramp from the surface through the accent to the text), and a series of
  the accent's hue is orange instead. `mix dev` shows the gallery in each
  (`?sumi=smoke`). See the Theming guide.
- `selected` on `<.chart>`: the marks that stand out, the others faded,
  by their values by channel as `select` sends them (`%{"x" => "North"}`).
  The chart draws again in place when only the selection changes. See the
  Live guide, "Clicks on marks".

### Fixed

- The Sumi theme gave Sumi's dark themes other than Ink the light palette,
  and Sumi's light themes other than Paper the dark one on a system in
  dark mode. Its sequential ramp was blade's in every theme.

## [0.6.1] - 2026-10-24

### Fixed

- The hook reads `phx-target` each time it sends an event, so a chart
  that a render of the LiveView gives a target after it mounted sends to
  it (it sent to the LiveView).

## [0.6.0] - 2026-10-24

A click on a mark sends its values: `select` on `<.chart>`.

### Added

- `select` on `<.chart>`: the event a click on a mark sends, or Enter on
  the mark the keyboard is on, with the chart's `id` and the mark's
  values by channel as the data has them (a category's name, a time's ISO
  text, a number). On a line chart's crosshair, the `x`. It goes where
  `phx-target` says. See the Live guide, "Clicks on marks".

## [0.5.0] - 2026-10-24

A number's history under it: a `spark` channel for `number` and `trend`.

### Added

- A `spark` channel for `number` and `trend`: the number's history as a
  small line under it, its value's field by the spark's (a time, in its
  order), ending on its last point, the number itself. Drawn on the
  server, as the number is; in the first color of the series, as high as
  `--fude-spark-height`. In a spec, `"spark"` on the layer's channels. See
  the Charts guide.

## [0.4.0] - 2026-10-24

A chart that fills its box, as a dashboard's card, and draws again as the
box is resized.

### Added

- `height={:fill}`: a chart takes the height its box gives it, as a
  dashboard's card, and draws again when the box changes height, as it
  does when it changes width. At least 120 pixels. See the Charts guide.

## [0.3.0] - 2026-10-24

A chart's data in the plot's place, and a chart's Data that stays open as
the LiveView renders it.

### Added

- `table={:swap}`: a chart's data in its place, at its size, behind a
  **Data** button; the table scrolls in the plot's box, its header stays.
  For a box of a fixed size, as a dashboard's card, which the table below
  stretched. `table` takes `true` (or `:below`, the default), `:swap` or
  `false`. See the Charts guide.

### Fixed

- A chart's Data, opened, closed again when the LiveView rendered the
  chart again: its new data, or the page around it (Lotus Web's dashboard
  selects a card on the click that opens it). It stays as the person left
  it.

## [0.2.0] - 2026-10-23

Richer tooltips, a right axis, color schemes, funnels and sparklines of
their own, and digits on a channel; stacks in the order of their series,
and tooltip fields shown.

### Fixed

- A bubble map colored by a category drew every circle in one color, with
  no legend (#18): a value channel of text (a map's or a heatmap's color)
  was summed as if it were a number. It now groups the rows, as a
  scatter's color does; a color of numbers is still summed. From a
  `Fude.query/2`, the schema's type of the field says which.

- The fields of a `tooltip` channel never reached the tooltip (#17): only
  their titles went to the browser, and it did not show them. Their
  values now go with each mark (aggregated where a mark groups rows: by
  the field's own aggregate, a sum of numbers, or the first value; times
  as times), and the tooltip shows them after the chart's own values, on
  a hovered mark and for each series on a crosshair. A chart from a
  `Fude.query/2` with tooltip fields reads them with its data, rather
  than aggregating in the database.
- Stacked bars and areas stacked their series in the order of the rows,
  so rows ordered by x only (a query `ORDER BY month`) gave each stack its
  own order: the bands of an area crossed and swapped from one x to the
  next. Each stack is now in the order of the series, as the legend has
  them (first seen, or the color channel's `sort`).

### Changed

- `format: :number` writes a value's decimals up to 2, under 1 too
  (0.125 was 0.125, is 0.13), so that money reads naturally.

### Added

- Richer tooltips (#15), from data the browser already has: in the
  `tooltip` list, `change: true` (the change from the series' point
  before, "▲ 12.4% vs February 2026"), `share: true` (of its stack, "34%
  of March", or of the total; the default on stacked marks), `rank: true`
  ("#2 of 14"), and `history: true` (a small line of the series, with the
  hovered mark). Each on a hovered mark, and for each series on a
  crosshair; a history on a hovered mark. The tooltip's layout: names on
  the left that wrap, values on the right in tabular figures, and what it
  adds under its value. In a spec, a map at the end of `"tooltip"`.
- Motion (#16): when the order of bars changes, each slides to its new
  place with its name and its value; bars that leave shrink back to the
  baseline. `animate: false` or `animate: [duration: ms]` on a chart (and
  `animate` on `<.chart>`, over it); reduced motion still wins. `frame` on
  a chart writes a sequence's label large in the plot's corner, for a race
  of bars. In a spec, `"animate"` and `"frame"`.

- A color scheme for a chart (#7): `scheme` on a `color` channel, by
  name, each in light and dark and readable with the common colour vision
  deficiencies: sequential `:blue` (the default), `:green`, `:orange`,
  `:purple`, `:gray`, `:viridis`; diverging `:red_blue` and `:red_green`,
  through a neutral at `mid` (0 unless given); categorical
  `:categorical` (the default) and `:okabe_ito`. Or a list of colors: a
  ramp for numbers, a color for each category. Each named scheme is a
  custom property (`--fude-scheme-green`). In a spec, `"scheme"` and
  `"mid"` on the channel; saved specs keep their colors.
- Funnels (#8): `color` (`color: :stage` a color for each stage, with no
  legend), `step: true` (each stage lighter than the one before), and
  `labels: :inside | :outside | false` (`:outside` as before); a label
  inside a bar too narrow for it goes outside, and one inside takes the
  text color that reads on its bar.
- Sparklines (#9): `area: true` (a fill under the line, fading down),
  `points: :last | :extremes`, and `value: true` (the last value at the
  end of the line, in y's format). With no height, a sparkline fills the
  height of its box, and is 48 pixels in a box with none.
- The SVG export draws gradients.
- `digits` on a channel: how many decimals `:number`, `:compact`,
  `:percent` and currencies write, from 0 to 20
  (`value: [field: :revenue, format: :number, digits: 0]` writes
  6,893,914). A trend's change takes the digits of its value. Axis ticks
  keep the decimals their step needs. In a spec, `"digits": 0` on the
  channel; nothing changes for saved specs.
- The default of a single value is documented: with no format, exact
  under 100,000 and compact from there.

- The single values (`number`, `trend`, `gauge`, `progress`) fill their
  box, as a tile of a dashboard does, and are centered in it: the number,
  the gauge's arc and the progress bar grow with the box (container
  queries), and the number narrows to fit its width. The box is the
  chart's `height` when it has one. `align: :start` keeps them at the
  start at a fixed size, for a number inline in a page; in a spec,
  `"align": "start"`, and specs without it center.
- A pass on the single values' type: tabular figures, a trend's change as
  a pill tinted by its direction, then its label; a progress's label and
  its share of the goal (`85%`) above a bar with round ends, as thick as
  `--fude-progress-height`.
- A right axis: `y: [field: :revenue, axis: :right]` puts a layer on a y
  scale of its own, drawn on the right of the plot, for two measures of
  other units over each other (bars of orders, a line of revenue):
  - the layers on the left share their scale, those on the right theirs;
  - with no color channel, the right axis's layers take the second color
    of the order, and each axis's title its layers' color;
  - the crosshair's tooltip lists the bars at the pointer with the lines;
  - in a spec, `"axis": "right"` on the channel.

## [0.1.0] - 2026-10-23

### Added

- Charts from one line of Elixir, in `Fude`: `bar/2` (and
  `horizontal: true`), `line/2`, `area/2`, `scatter/2`, `bubble/2`,
  `pie/2`, `donut/2`, `histogram/2`, `heatmap/2`, `waterfall/2`,
  `funnel/2`, `sparkline/2`, `choropleth/2`, `bubble_map/2`, `rule/2`,
  `text/2`, and the single numbers `number/2`, `trend/2`, `gauge/2` and
  `progress/2`; `layers/3` for several over each other.
- Channels as a field, an aggregate (`{:sum, :revenue}`), a unit of time
  (`{:month, :created_at}`) or bins (`{:bin, :total}`), or the full form
  with a type, a sort, a format, a title, a scale and a stack.
- `<.chart>` in `Fude.Components`: the marks on a canvas and the words as
  SVG; a crosshair and one tooltip for every series; a legend that
  highlights and hides; keyboard navigation with announcements; a table
  of the data.
- Charts that move: marks go from where they were to where they are when
  the data changes.
- Words as a graphics desk sets them (`Fude.title/3`): titles,
  subtitles, captions and sources; labels at line ends; value labels;
  category names that wrap or stagger before they thin.
- Notes on the data (`Fude.annotate/3`): labels with a connector, bands
  and lines.
- Small multiples (`Fude.facet/3`): a panel for each value, on shared
  scales, with one legend.
- Maps of the world's countries (Equal Earth) and the US states (Albers
  USA), by code or name, registered by the pages that draw them
  (`registerMap`).
- Data as lists of maps, as a query result (`%{columns, rows}`), or as an
  Ecto query grouped and aggregated in PostgreSQL, MySQL or SQLite
  (`Fude.query/3`).
- `Fude.Spec.dump/1` and `load/1`: a chart as JSON with a version,
  migrated forward, with errors at their path and a suggestion.
- `Fude.Live.append/5` to stream rows into a chart, and
  `Fude.Live.export/3` and `<.chart export>` for SVG and PNG files.
- The rules of ticks, nice domains, bins and units of time, the same on
  the server and in the browser, tested on both with one fixture.
- `Fude.Test`, to read what a chart shows in `Phoenix.LiveViewTest`.
- The Sumi theme (`fude-sumi.css`), dark mode, reduced motion and forced
  colors.
- `Fude.Issho`, with Issho: a chart as a room's shared state, that people
  change with `Fude`'s functions (`Fude.Issho.change/3`) and agents with
  the `read_chart` and `change_chart` tools, refused when a change makes
  it invalid; the people's pointers on its marks, in its data's terms
  (`Fude.Issho.Place`, `<.chart issho>`).
- An `"id"` for a layer and an annotation of a spec.
- `mix fude.install`.

[Unreleased]: https://github.com/hattoriai/fude/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/hattoriai/fude/releases/tag/v0.8.0
[0.7.0]: https://github.com/hattoriai/fude/releases/tag/v0.7.0
[0.6.1]: https://github.com/hattoriai/fude/releases/tag/v0.6.1
[0.6.0]: https://github.com/hattoriai/fude/releases/tag/v0.6.0
[0.5.0]: https://github.com/hattoriai/fude/releases/tag/v0.5.0
[0.4.0]: https://github.com/hattoriai/fude/releases/tag/v0.4.0
[0.3.0]: https://github.com/hattoriai/fude/releases/tag/v0.3.0
[0.2.0]: https://github.com/hattoriai/fude/releases/tag/v0.2.0
[0.1.0]: https://github.com/hattoriai/fude/releases/tag/v0.1.0
