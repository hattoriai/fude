# Collaboration

Fude draws charts on its own. A chart that others change too (a report
two people build at once, a chart an agent makes beside you) is a
document of an [Issho](https://hex.pm/packages/issho) room: `Fude.Issho`,
compiled when Issho is in your deps.

```elixir
{:issho, "~> 0.4"}
```

Everyone changes it the same way. People change it in your LiveView with
`Fude`'s own functions; agents change it with tools that send the same
changes; and every change, whoever made it, must leave a valid chart.

## The document

A shared chart is the chart's spec as the room's shared state
(`Issho.State`), with an id for each layer and annotation. Define it in
your policy, from the chart your app keeps, and save it in `:on_change`:

```elixir
def document(_who, "report:" <> id) do
  report = Reports.get!(id)
  Fude.Issho.document(report.chart, on_change: &Reports.save_chart(report, &1, &2))
end
```

`:on_change` gets the chart after each change, and the change's context
(who made it is `:by`). It answers `:ok`, or `{:error, reason}` to
refuse the change: a chart your app does not allow, a person who may not
change it.

A change that makes the chart invalid is refused before `:on_change`: a
kind that is not one, an aggregate misspelled, a channel a kind needs and
does not have. The person or the agent who made it gets every error, a
layer by its id:

```text
the chart is not valid:
  layers.l7Kq2.y.aggregate: must be one of "count", "sum", ...; did you mean "sum"?
```

## In a LiveView

```elixir
def mount(%{"id" => id}, _session, socket) do
  room = "report:" <> id
  report = Reports.get!(id)

  if connected?(socket),
    do: {:ok, _} = Issho.Live.join(MyApp.Issho, socket.assigns.current_user, room)

  {:ok,
   socket
   |> assign(sales: Sales.by_region())
   |> Fude.Issho.assign(:chart, room, room, report.chart)}
end

def handle_event("title", %{"title" => title}, socket) do
  :ok = Fude.Issho.change(socket, :chart, &Fude.title(&1, title))
  {:noreply, socket}
end

def handle_event("goal", %{"goal" => goal}, socket) do
  :ok =
    Fude.Issho.change(socket, :chart, fn chart ->
      Fude.annotate(chart, :line, y: String.to_integer(goal), text: "Goal")
    end)

  {:noreply, socket}
end
```

```heex
<.chart id="revenue" spec={@chart} data={@sales} issho="report:7" />
```

`@chart` is the chart's spec, and changes as anyone changes it: this
LiveView, another person's, an agent. The chart moves to its new form as
it does for new data.

`Fude.Issho.change/3` takes a function of the chart and sends only what
it changed: a key of the chart, a key of a layer or an annotation, a
layer added, moved or removed. Two people who change two layers at once
both have their change; two who change one title, the last one's.

Your server changes a shared chart through the room too, with
`Issho.transact/4` and the operations of `Fude.Issho.ops/2`.

## Pointers

The `issho` attribute of `<.chart>` is the chart's document. With
Issho's pointers on the page, the people of the room see each other's
pointer on the chart, at the same data on every screen: on the same bar,
the same time of a line, the same country, whatever the size of the
chart on each screen.

A place in a chart is in its data's terms (`Fude.Issho.Place`):

```elixir
%{"datum" => %{"x" => "Europe", "color" => "Online"}}  # a bar
%{"datum" => %{"x" => "2026-03-01"}}                   # a time, across a line chart
%{"datum" => %{"region" => "BRA"}}                     # a country
```

## Agents

An agent uses a shared chart as a person does, with Issho's room tools
and Fude's:

| Tool | |
| --- | --- |
| `read_chart` | the chart's spec, and what it shows: its words, a description, and the table of its data as it draws it |
| `change_chart` | the spec as the agent wants it; only what changed is sent |
| `point` (Issho's) | a pointer on a mark, at a place of the chart |
| `update_state` (Issho's) | operations on the spec by paths, with the same check |

```elixir
tools = Issho.Tools.room() ++ Fude.Issho.tools()
```

The chart's data is your app's. `read_chart` tells an agent what a
chart shows when your app gives it the data, for the agent:

```elixir
config :fude, Fude.Issho, data: {MyApp.Reports, :chart_data}

def chart_data("report:" <> id, ctx), do: {:ok, Reports.sales(id, ctx.opts[:on_behalf_of])}
def chart_data(_document, _ctx), do: {:error, "There is no such report."}
```

An agent that rewrites a spec and leaves out the ids changes the layers
it had, in their order, rather than replacing them.
