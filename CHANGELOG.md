# Changelog

All notable changes to Fude are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Fude follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - Unreleased

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
