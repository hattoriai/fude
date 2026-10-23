# Testing

`Fude.Test` reads what a chart shows in `Phoenix.LiveViewTest`, from
what the server sent the browser: no browser needed.

```elixir
import Fude.Test

test "shows the revenue of each region", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/sales")

  assert kind(view, "revenue") == "bar"
  assert series(view, "revenue") == ["Online", "Retail"]
  assert [%{"Region" => "North", "Revenue" => 120, "Channel" => "Online"} | _] = data(view, "revenue")
end
```

## Reading

* `chart(view, id)` - all that the server sent: kind, scales, layers.
* `kind(view, id)`, `title(view, id)`, `description(view, id)`.
* `series(view, id)` - the names of the series (the colors), in order.
* `data(view, id)` - a map for each mark, by the titles of the columns,
  as the chart's table has them: categories by their names, times as
  `Date` or `DateTime`.
* `value(view, id)` - the number of a `number`, `trend`, `gauge` or
  `progress`.
* `error(view, id)` - why the chart does not draw, or `nil`.

## Streaming

`Fude.Live.append/5` pushes an event; assert it with
`assert_push_event(view, "fude:append", %{id: "load"})`.
