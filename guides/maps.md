# Maps

Two kinds draw on a map: a `choropleth` colors each region by a value,
and a `bubble_map` puts a circle at each region's center, sized by a
value.

```elixir
Fude.choropleth(users, region: :country, color: :users, title: "Where the users are")
Fude.bubble_map(stores, region: :state, size: :stores, map: "us-states")
```

## The maps

| Map | Regions | Codes |
| --- | --- | --- |
| `"world"` | the countries of Natural Earth (1:110m), in the Equal Earth projection, without Antarctica | ISO 3166 alpha-3 (`"PRT"`), alpha-2 (`"PT"`), number (`"620"`), the name, and its other English names (`"Russian Federation"`) |
| `"us-states"` | the states of the US Census Bureau (1:10m), in Albers USA with Alaska and Hawaii | postal code (`"CA"`), FIPS (`"06"`), `"US-CA"`, the name |

A region of the data is found by any of its codes, in any case. A name
that two regions have is the one whose own name it is (`"Congo"` is the
Republic of the Congo). The regions of the data that are not on the map
are listed in the browser's console.

## Registering the maps

The maps are files of the package, projected once, so the browser only
draws them. A page loads only the maps it registers:

```js
import { registerMap } from "fude"
import world from "fude/maps/world.json"

registerMap("world", world)
```

or from a URL, fetched when a chart first needs it:

```js
registerMap("us-states", "/fude/maps/us-states.json")
```

A map of your own is a JSON file of the same shape (see
`assets/scripts/maps.mjs`, which makes Fude's from TopoJSON):
`{"fude_map": 1, "name", "width", "height", "regions": [{"id", "codes",
"name", "names", "path", "center"}]}`, with each region's `path` as SVG
path data in the map's units.
