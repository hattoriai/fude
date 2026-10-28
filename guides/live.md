# Live

## Charts that follow their data

A chart is drawn from its assigns. When the chart or its data changes,
the server sends the new chart, and the browser draws it again in place:
each bar, point, slice and line moves from where it was to where it is,
new marks grow from the baseline, and the ones that left shrink back
into it as they fade. When the order of the bars changes (a sort by
value, and values that overtake each other), each bar slides to its new
place, its name and its value with it. A theme or a size that changes
draws again without moving.

A sequence of renders is a race of bars: sort the bars by their value,
and give each render a `frame`, which the chart writes large in the
corner of its plot, under the marks:

```elixir
def handle_info({:tick, month}, socket) do
  chart =
    Fude.bar(Sales.by_region(month), x: [field: :region, sort: :"-y"], y: :revenue,
      horizontal: true, labels: true, frame: Calendar.strftime(month, "%B %Y"))

  {:noreply, assign(socket, chart: chart)}
end
```

```elixir
def handle_info({:order, _order}, socket) do
  {:noreply, assign(socket, sales: Sales.by_region())}
end
```

### What a render sends

The browser gets the chart's config, in the page and again in each
render that changes it. Long columns go packed (`Fude.Wire`): a time
series' days as steps of a day, numbers of a few decimals as whole
steps, so that 4 series of 1,000 days are 35 KB, not 89 KB. A column is
packed only when it comes back as the very same numbers. Every render
still sends the whole config of a chart that changed: for one new point
at a time, append it (below).

The socket sends what LiveView sends as it is. Its messages compress
well (a chart's config to a quarter or less), with `compress: true` on the
socket of your endpoint, if your proxies pass the compressed messages:

```elixir
socket "/live", Phoenix.LiveView.Socket,
  websocket: [connect_info: [session: @session_options], compress: true]
```

## Streaming points

For a chart that grows a point at a time, `Fude.Live.append/5` sends only
the new rows. The browser adds them to the chart's marks, keeps the last
`max`, fits its scales, and moves; a new point comes in from where its
line was.

```elixir
def mount(_params, _session, socket) do
  if connected?(socket), do: Phoenix.PubSub.subscribe(MyApp.PubSub, "readings")
  {:ok, assign(socket, readings: Readings.last(60))}
end

def handle_info({:reading, reading}, socket) do
  {:noreply, Fude.Live.append(socket, "load", load_chart(), [reading], max: 60)}
end

defp load_chart, do: Fude.line(x: :at, y: :load, title: "Load")
```

```heex
<.chart id="load" chart={load_chart()} data={@readings} />
```

The new rows go through the chart's rules (types, units of time,
formats). Appending suits a chart whose marks are its rows: lines, areas
and points with no aggregate. A chart that sums or counts draws again
from its assigns instead.

## Clicks on marks

`<.chart select="pick">` sends `"pick"` when a person clicks a mark, or
presses Enter on the mark the keyboard is on, with the chart's `id` and
the mark's values by channel, as the data has them: a category's name, a
time's ISO text, a number. A dashboard filters by the bar it is given:

```elixir
<.chart id="revenue" chart={@chart} select="pick" />

def handle_event("pick", %{"id" => "revenue", "x" => region}, socket) do
  {:noreply, assign(socket, region: region)}
end
```

A bar sends its `x`, `y` and `color` (its series); a slice of a pie, its
`color`; a region of a map, its `region`. A line chart sends
the `x` at its crosshair: a click there is on a time, not on one line.
The event goes where `phx-target` says, as LiveView's own do. A mark a
click sends shows a pointer.

`selected` makes the marks it names stand out and fades the others: the
values by channel, as `select` sends them. A dashboard that filters by a
bar shows that bar:

```elixir
<.chart id="revenue" chart={@chart} select="pick" selected={@region && %{"x" => @region}} />
```

A mark stands out when each value is its own (`%{"x" => "North"}` picks
North's bars, of every series). With no selection, or none of its marks
in the data, no mark fades. The chart draws it again in place, with no
move, when only the selection changes.

## Brushing a range

`brush` on a chart lets a person drag across its x axis to choose a
range, shaded as they drag, with the range written above it ("Mar – May
2026"). It does one of two things:

```elixir
Fude.line(orders, x: :day, y: {:sum, :total}, brush: :zoom)
Fude.bar(orders, x: {:month, :placed_on}, y: {:count, :id}, brush: :select)
```

* `:zoom` - the chart zooms its x axis to the range, in place, its marks
  moving there. A **Reset zoom** button, a double click or Escape goes
  back. The server does not hear of it.
* `:select` - the range goes to the server as the event `"fude:brush"`,
  with the chart's `id` and its `from` and `to`, where `phx-target` says;
  what it means is the app's. The range stays shaded until the server's
  next render, or the person clears it (a **Clear range** button, a
  double click, Escape). `Fude.Live.brush_range/1` reads it:

```elixir
def handle_event("fude:brush", %{"id" => "orders"} = params, socket) do
  {from, to} = Fude.Live.brush_range(params)
  {:noreply, socket |> assign(period: {from, to}) |> load_orders()}
end
```

The range is in the axis's terms, both ends included: a time with a
unit snaps to whole units (`from` is the first month, `to` the last),
and comes as a `Date` for a unit of a day or more, a `DateTime` for one
of a time of a day; a number is a number (a histogram's out to the
edges of its bins). The page hears the same range as a DOM event,
`fude:brush` on the chart's element, for a page with no LiveView.

A brush is across the x axis of times and numbers: lines, areas,
points, histograms and bars over time. On a phone it starts with a long
press, so that a swipe still scrolls the page; on the keyboard, Shift
and the arrows choose a range, and Enter commits it. A brush on a panel
of small multiples zooms them all, and sends the chart's range.

## Linked hover

Charts of the same months on a dashboard (revenue, orders, refunds) can
show the same place together. Give them the same `link`:

```heex
<.chart id="revenue" chart={@revenue} link="months" />
<.chart id="orders" chart={@orders} link="months" />
```

Hovering March on one, or moving to it with the keyboard, shows March on
every chart of the link: a line or an area chart draws its crosshair
there, with each line's value by its dot, and a bar chart brings that
month's bars forward. The tooltip shows only on the hovered chart, so
that the page is not covered in tooltips. Leaving clears them all.

The charts match by the value, not by where it is on the screen: a time
within the coarser of the two axes' units (a day in March is March on a
chart of months; March is its first day on a chart of days), a category
by its name, a number by itself. A chart that does not have the value
shows nothing. The panels of small multiples with a `link` are in it too.

Linking is in the browser only, with no event to the server, so it is as
fast as the hover. A chart that follows another says what it shows in
its stage's `data-fude-linked` (the crosshair's x, or how many marks),
for a page and its tests to read.

## Export

`<.chart export>` has buttons that save the chart as SVG, or as PNG at
twice its size, with its title, legend and source as on the page. From
the server, `Fude.Live.export(socket, "revenue", :png)` has the browser
save it.
