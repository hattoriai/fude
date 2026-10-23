# Backlog

Known gaps in Fude, each to become an issue.

## Masu: the query of what a grid shows

A chart of a Masu grid takes `Masu.Live.selected/1`, which gives the
grid's filtered query only when every row is selected. Masu could give
the query of what a grid shows, with no selection
(`Masu.Live.query/1`), so that a chart beside a grid follows its
filters. The change is Masu's; Fude takes any Ecto query already.

## Livebook

A separate package, `fude_livebook`: a chart as a Kino, the specs of
cells saved in the notebook, and a smart cell that builds a chart from a
dataframe or a query.

## A time zone for a chart

Times are drawn and written in UTC. A chart's `time_zone`, in the units
of time on the server (a day in Lisbon, not in UTC), in the database
(`AT TIME ZONE`), and in the browser's formats.

## Two y axes

A layer on a second y scale, on the right, for two measures of different
units.

## Points at a longitude and a latitude

`bubble_map` places circles at a region's center. Points of their own
need the projections in the browser (Equal Earth and Albers USA), and a
`lon` and `lat` channel.

## More maps, and tiles

The regions of other countries (Brazil's states, Europe's NUTS), from a
TopoJSON the app gives through `registerMap`, projected in the browser.
Street maps on tiles are an add-on.

## SVG on the server

The SVG and PNG files are made in the browser. A chart as SVG made on
the server, for an email or a PDF with no browser, needs the text
measures of the browser (a table of widths of the theme's fonts).

## Small multiples of a query

A facet of a `Fude.query/3` reads the query's rows. Grouping by the
facet field in the database would read the groups.

## Appending to a chart of groups

`Fude.Live.append/5` suits charts whose marks are their rows (lines,
points). Appending to a chart that aggregates (a bar of sums) needs the
browser to fold a row into its group; the table under a streamed chart
is the one of its last render.

## Brushing and zooming

A range of a chart chosen with the pointer or the keyboard, sent to the
LiveView as an event (a filter for the other charts of a page), and
zooming a time axis.

## Messages in the chart's locale

The few words that Fude writes itself ("Data", "Total", the
descriptions for screen readers) are in English. Gettext on the server,
and the words in the wire.

## A binary wire

The wire is JSON. A binary encoding of the columns (typed arrays) for
charts of hundreds of thousands of points, if a benchmark shows it pays.

## Migrating Vega-Lite specs

A script from the common Vega-Lite specs (bar, line, area, point, arc,
rect, with their encodings) to Fude specs, for apps that move from Vega.
