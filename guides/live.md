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

## Export

`<.chart export>` has buttons that save the chart as SVG, or as PNG at
twice its size, with its title, legend and source as on the page. From
the server, `Fude.Live.export(socket, "revenue", :png)` has the browser
save it.
