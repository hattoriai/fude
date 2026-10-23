# Specs

A chart is plain data. `Fude.Spec.dump/1` gives a map with string keys
and JSON values, to keep in a `:map` column, a JSON file or a message;
`Fude.Spec.load/1` takes it back, and `load(dump(chart))` is the chart.

```elixir
spec = Fude.Spec.dump(Fude.bar(x: :region, y: {:sum, :revenue}, title: "Revenue"))
#=> %{"fude" => 1, "kind" => "bar", "title" => "Revenue", "x" => "region",
#     "y" => %{"field" => "revenue", "aggregate" => "sum"}}

{:ok, chart} = Fude.Spec.load(spec)
```

A spec names its data and does not hold it; the chart gets it when it
draws:

```heex
<.chart id="revenue" spec={@report.chart} data={@sales} />
```

`Fude.Spec.dump(chart, data: true)` puts the data in, under
`"datasets"`, for a file that stands alone.

## The shape

A chart of one layer has its kind, channels and options at the top; a
chart of several has them in `"layers"`. A channel is a field's name, or
a map of the keys of `Fude.Channel`; a constant is `{"value": 1000}`.
`"annotations"` and `"facet"` follow the chart's notes and its small
multiples.

## Versions

Every spec carries its version (`"fude": 1`). A later Fude loads the
specs of every earlier version, migrating them forward one version at a
time: a saved chart keeps working. A spec of a newer version than the
Fude that loads it is refused, with that reason.

## Errors

`load/1` checks the whole spec and gives every error, each with where it
is and what to do:

```elixir
Fude.Spec.load(%{"fude" => 1, "kind" => "bar", "x" => "region", "y" => %{"field" => "revenue", "aggregate" => "summ"}, "colour" => "channel"})
#=> {:error, [
#     %{path: ["colour"], message: ~s|is not a key of a bar chart; it takes x, y, color, ...; did you mean "color"?|},
#     %{path: ["y", "aggregate"], message: ~s|must be one of "count", "sum", ...; did you mean "sum"?|}
#   ]}
```

`<.chart spec={...}>` shows them in place of the plot, and does not
raise. A spec makes no atom of what it says: a spec from a person or an
agent is safe to load.
