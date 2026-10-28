# Maps

Two kinds draw on a map: a `choropleth` colors each region by a value,
and a `bubble_map` puts a circle at each region's center, sized by a
value.

```elixir
Fude.choropleth(users, region: :country, color: :users, title: "Where the users are")
Fude.bubble_map(stores, region: :state, size: :stores, map: "us-states")
```

A choropleth's `shade` makes each region's color lighter as a number is
less: each region in the color of the party that leads it, darker as its
lead is larger. The legend has the colors and a ramp of the shade; the
tooltip, both.

```elixir
Fude.choropleth(leads, region: :state, color: :leader, shade: [field: :lead, title: "Lead, points"],
  map: "us-states")
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
`{"fude_map": 1, "name", "width", "height", "outline", "regions": [{"id",
"codes", "name", "names", "path", "center"}]}`, with each region's `path`
as SVG path data in the map's units. `outline`, when there is one, is
drawn as a hairline in the grid's color: the frames of a map's insets
(islands moved beside the mainland), or a globe's edge.

GeoJSON often winds its polygons the other way round from d3 (as RFC 7946
has it), which d3 reads as the whole globe but the region: each region
would be a square over the map. The script turns round any polygon larger
than a hemisphere before it projects it.

A bubble map sizes its largest circle by how far apart the regions are,
so that a map of many small regions (municipalities, counties) keeps its
circles apart.
