# Live

## Charts that follow their data

A chart is drawn from its assigns. When the chart or its data changes,
the server sends the new chart, and the browser draws it again in place:
each bar, point, slice and line moves from where it was to where it is,
new marks grow from the baseline, and the ones that left fade. A theme
or a size that changes draws again without moving.

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

## Export

`<.chart export>` has buttons that save the chart as SVG, or as PNG at
twice its size, with its title, legend and source as on the page. From
the server, `Fude.Live.export(socket, "revenue", :png)` has the browser
save it.
