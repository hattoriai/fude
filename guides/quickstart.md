# Quickstart

A first chart in a LiveView, from data you already have.

## 1. Add the dependency

```elixir
{:fude, "~> 0.3"}
```

```sh
mix deps.get
mix fude.install
```

The installer adds the `Fude` hook to `assets/js/app.js` and the style
sheet to `assets/css/app.css` (see the README for the manual steps).

## 2. Import the components

In the `html_helpers` of your web module:

```elixir
import Fude.Components
```

## 3. Draw a chart

```elixir
defmodule MyAppWeb.SalesLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, sales: Sales.by_region())}
  end

  def render(assigns) do
    ~H"""
    <.chart id="revenue" chart={Fude.bar(@sales, x: :region, y: :revenue, title: "Revenue by region")} />
    """
  end
end
```

`Sales.by_region/0` gives a list of maps (`%{region: "North", revenue:
120}`), or a query result (`%{columns: [...], rows: [...]}`).

The chart has its title, its axes, a tooltip on each bar, the keyboard
(Tab to the chart, then the arrows), and a table of its data under a
toggle. When `@sales` changes, the bars move to their new heights.

## 4. Say more

A channel can aggregate, take a unit of time, or put numbers in bins:

```elixir
Fude.line(orders, x: {:month, :placed_on}, y: {:sum, :total}, color: :channel)
Fude.histogram(orders, x: :total, bins: 30)
```

A chart has words, as a graphics desk sets them:

```elixir
Fude.line(orders, x: {:month, :placed_on}, y: [field: :total, aggregate: :sum, format: {:currency, "EUR"}])
|> Fude.title("Online keeps growing", subtitle: "Monthly revenue, in euros")
|> Fude.annotate(:label, x: ~D[2026-03-01], y: 76_000, text: "The new shop opens")
```

## 5. Let the database count

For a table of many rows, give the chart a query: the database groups
and sums, and the chart reads the groups.

```elixir
Order |> Fude.query(Repo) |> Fude.bar(x: :status, y: {:count, :id})
```

Next: [Charts](charts.md) for every kind, [Data](data.md) for the
sources, [Telling the story](story.md) for the words and notes.
