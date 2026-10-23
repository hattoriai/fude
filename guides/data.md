# Data

A chart draws data of any of these forms:

* a list of maps, with atom or string keys;
* a map of `:columns` and `:rows`, as a query result has them
  (`Postgrex.Result`, `MyXQL.Result`, Lotus's results), with atom or
  string keys;
* an Ecto query or schema with its repo, `Fude.query(queryable, repo)`,
  which the database groups and aggregates.

The values become what the browser draws: a `Decimal` a number; a
`Date`, `NaiveDateTime` or `DateTime` a time (a date at its midnight, in
UTC); `nil` a gap; anything else a category, by its text. No value has to
be cast for the browser.

Only the fields that a chart draws are read: a query of thirty columns
for a chart of two reads two.

## In memory

The server makes the chart from the rows: it groups and aggregates them,
puts them in bins, stacks them, and sends the browser only what it
draws. 200,000 rows take about 0.2 seconds (`mix run bench/compile.exs`).

## In the database

```elixir
from(o in Order, where: o.shop_id == ^shop.id)
|> Fude.query(Repo)
|> Fude.line(x: {:month, :placed_at}, y: {:sum, :total}, color: :channel)
```

For each layer, one query groups by the channels that are not aggregated
(a field, its unit of time, its bin) and aggregates the others, in a
subquery so that each database groups by columns. A histogram reads the
least and the greatest value first, for its bins. PostgreSQL, MySQL and
SQLite run them, each with its own functions of dates; their results are
the same as in memory (the tests run on the three).

A layer with no aggregate (a scatter of points), a `median`, or small
multiples read the fields the chart draws instead, at most `:limit` rows
(100,000 when not given):

```elixir
Fude.query(Order, Repo, limit: 20_000, repo_opts: [prefix: "tenant_42"])
```

The query keeps its own `where` and `join`; its `order_by` is dropped for
the groups, which come in the order of their keys.

## Masu's grids

A grid of Masu gives its filtered rows as an Ecto query
(`Masu.Live.selected/1` with every row selected): a chart of what the
grid shows is a chart of that query.

```elixir
{:query, query} = Masu.Live.selected("orders")
Fude.bar(Fude.query(query, Repo), x: :status, y: {:count, :id})
```

## Several datasets

A chart names its data (`data: "sales"`, `"data"` when not given), so
that a saved spec gets it again when it draws:

```heex
<.chart id="revenue" spec={@report.chart} data={@sales} />
```
