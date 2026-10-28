# Known limits

What Fude does not do yet. Each is a good first issue to open.

* **Times are in UTC.** Times are drawn and written in UTC; a time zone
  for the chart is to come.
* **Maps.** The world and the US states; street maps with tiles are an
  add-on to come. Points at a longitude and a latitude are to come.
* **The server's SVG.** The SVG and PNG files are made in the browser. A
  chart as SVG on the server (for an email or a PDF, with no browser) is
  to come.
* **Appending** suits charts whose marks are their rows.
* **Small multiples of a query** read the query's rows, not its groups.
* **The data table** needs JavaScript, as the plot does: the hook writes
  it from the chart's config (small multiples have the server's).
* **Brushing** is across the x axis, of times and numbers (bands of
  months too), not of categories or of a horizontal bar's amounts.
* **Messages.** The few words that Fude writes itself ("Data", "Total",
  the descriptions) are in English.
