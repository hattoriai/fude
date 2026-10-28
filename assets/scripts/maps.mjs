// Makes Fude's maps (assets/maps/*.json): regions projected once, as SVG
// path data that a canvas draws as it is (Path2D), with each region's
// codes, names and center. The maps are committed; run this only to make
// them again:
//
//   cd assets && npm i --no-save world-atlas@2.0.2 us-atlas@3.0.1 \
//     i18n-iso-countries@7.14.0 d3-geo@3.1.1 topojson-client@3.1.0
//   node scripts/maps.mjs maps
import { readFileSync, writeFileSync } from "node:fs";
import { feature } from "topojson-client";
import { geoArea, geoEqualEarth, geoIdentity, geoPath } from "d3-geo";
import countries from "i18n-iso-countries";

const out = process.argv[2];
const load = (p) => JSON.parse(readFileSync(new URL(`../${p}`, import.meta.url)));

// A path context that writes rounded points and skips those under a
// threshold from the last: smaller files, the same picture at the size.
function writer(precision, threshold) {
  let d = "";
  let last = null;
  const r = (v) => Math.round(v * precision) / precision;
  return {
    moveTo(x, y) { d += `M${r(x)},${r(y)}`; last = [x, y]; },
    lineTo(x, y) {
      if (last && Math.hypot(x - last[0], y - last[1]) < threshold) return;
      d += `L${r(x)},${r(y)}`; last = [x, y];
    },
    closePath() { d += "Z"; last = null; },
    arc() {},
    result() { const s = d; d = ""; return s; },
  };
}

// The center of a region: of its largest polygon, so that France is in
// Europe and the United States not in Alaska.
function center(f, path) {
  const g = f.geometry;
  let geometry = g;
  if (g.type === "MultiPolygon") {
    let best = null;
    for (const coords of g.coordinates) {
      const poly = { type: "Polygon", coordinates: coords };
      const a = path.area(poly);
      if (!best || a > best[0]) best = [a, poly];
    }
    geometry = best[1];
  }
  const [x, y] = path.centroid(geometry);
  return [Math.round(x * 10) / 10, Math.round(y * 10) / 10];
}

// Each polygon wound as d3 draws it, clockwise. Much GeoJSON winds its
// rings the other way (as RFC 7946 has it), which d3 reads as the whole
// globe but the region: drawn, a square over the map. A polygon larger than
// a hemisphere is turned round. (Projected data, through geoIdentity, has
// no sphere: it is left as it is.)
function rewind(feature) {
  const g = feature.geometry;
  if (!g || (g.type !== "Polygon" && g.type !== "MultiPolygon")) return feature;
  const polygons = g.type === "Polygon" ? [g.coordinates] : g.coordinates;
  for (const polygon of polygons) {
    if (geoArea({ type: "Polygon", coordinates: polygon }) > 2 * Math.PI) for (const ring of polygon) ring.reverse();
  }
  return feature;
}

function build({ name, about, features, projection, width, height, codes, aliases, outline, projected = false }) {
  if (!projected) features.forEach(rewind);
  const ctx = writer(10, 0.35);
  const path = geoPath(projection, ctx);
  const measure = geoPath(projection);
  const regions = features.map((f) => {
    path(f);
    const all = codes(f);
    const names = [...new Set([f.properties.name, ...(aliases ? aliases(f, all) : [])])];
    return { id: all[0], codes: all, name: f.properties.name, names, path: ctx.result(), center: center(f, measure) };
  }).filter((r) => r.path);
  let sphere = null;
  if (outline) { path(outline); sphere = ctx.result(); }
  const map = { fude_map: 1, name, about, width, height, outline: sphere, regions };
  writeFileSync(`${out}/${name}.json`, JSON.stringify(map));
  console.log(name, regions.length, "regions", Math.round(JSON.stringify(map).length / 1024), "KB");
}

// The world: Natural Earth's countries at 1:110m, in Equal Earth, without
// Antarctica.
{
  const topo = load("./node_modules/world-atlas/countries-110m.json");
  const all = feature(topo, topo.objects.countries).features;
  const features = all.filter((f) => f.id !== "010" && f.properties.name !== "Antarctica");
  const width = 960;
  const projection = geoEqualEarth().fitWidth(width, { type: "FeatureCollection", features });
  const [[, y0], [, y1]] = geoPath(projection).bounds({ type: "FeatureCollection", features });
  const height = Math.ceil(y1 - y0 + 2);
  projection.translate([projection.translate()[0], projection.translate()[1] - y0 + 1]);
  build({
    name: "world",
    about: "Countries of Natural Earth (1:110m, public domain), via world-atlas; Equal Earth projection; without Antarctica.",
    features, projection, width, height,
    codes: (f) => {
      const numeric = f.id;
      const a3 = numeric ? countries.numericToAlpha3(numeric) : null;
      const a2 = numeric ? countries.numericToAlpha2(numeric) : null;
      if (f.properties.name === "Kosovo") return ["XKX", "XK"];
      return [a3, a2, numeric].filter(Boolean).concat(a3 ? [] : [f.properties.name]);
    },
    aliases: (f, codes) => {
      const long = countries.getName(codes[0], "en", { select: "all" }) ?? [];
      return long;
    },
  });
}

// The United States: the states of the Census Bureau (1:10m, public
// domain), via us-atlas, already in Albers USA with Alaska and Hawaii.
{
  const topo = load("./node_modules/us-atlas/states-albers-10m.json");
  const features = feature(topo, topo.objects.states).features;
  const usps = { "01":"AL","02":"AK","04":"AZ","05":"AR","06":"CA","08":"CO","09":"CT","10":"DE","11":"DC","12":"FL","13":"GA","15":"HI","16":"ID","17":"IL","18":"IN","19":"IA","20":"KS","21":"KY","22":"LA","23":"ME","24":"MD","25":"MA","26":"MI","27":"MN","28":"MS","29":"MO","30":"MT","31":"NE","32":"NV","33":"NH","34":"NJ","35":"NM","36":"NY","37":"NC","38":"ND","39":"OH","40":"OK","41":"OR","42":"PA","44":"RI","45":"SC","46":"SD","47":"TN","48":"TX","49":"UT","50":"VT","51":"VA","53":"WA","54":"WV","55":"WI","56":"WY","60":"AS","66":"GU","69":"MP","72":"PR","78":"VI" };
  build({
    name: "us-states",
    about: "States of the U.S. Census Bureau (1:10m, public domain), via us-atlas; Albers USA projection, with Alaska and Hawaii.",
    features, projection: geoIdentity(), projected: true, width: 975, height: 610,
    codes: (f) => [usps[f.id], f.id, `US-${usps[f.id]}`].filter(Boolean),
    aliases: null,
  });
}
