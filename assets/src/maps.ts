// The maps of the map charts: regions projected once (scripts/maps.mjs),
// each as SVG path data that the canvas draws as it is. An app registers
// the maps it uses, as data or as a URL to fetch:
//
//   import world from "fude/maps/world.json"
//   registerMap("world", world)
//   registerMap("us-states", "/assets/fude/maps/us-states.json")

export interface MapRegion {
  id: string;
  codes: string[];
  name: string;
  names: string[];
  path: string;
  center: [number, number];
}

export interface FudeMap {
  fude_map: 1;
  name: string;
  about?: string;
  width: number;
  height: number;
  outline: string | null;
  regions: MapRegion[];
}

export interface LoadedMap {
  map: FudeMap;
  /** The region of a code or a name of the data, in any case. */
  find(value: unknown): number | undefined;
  path(index: number): Path2D;
}

const sources = new Map<string, FudeMap | string>();
const loaded = new Map<string, LoadedMap>();
const loading = new Map<string, Promise<LoadedMap>>();

/** Registers a map by its name: its data, or the URL of its JSON. */
export function registerMap(name: string, map: FudeMap | string): void {
  sources.set(name, map);
  loaded.delete(name);
  loading.delete(name);
}

/**
 * The map of a name: at once when it is loaded, a promise while it is
 * fetched, or null when no map has that name.
 */
export function loadMap(name: string): LoadedMap | Promise<LoadedMap> | null {
  const ready = loaded.get(name);
  if (ready) return ready;
  const pending = loading.get(name);
  if (pending) return pending;
  const source = sources.get(name);
  if (!source) return null;
  if (typeof source !== "string") return prepare(name, source);
  const promise = fetch(source)
    .then((response) => {
      if (!response.ok) throw new Error(`Fude: the map ${name} did not load (${response.status})`);
      return response.json() as Promise<FudeMap>;
    })
    .then((map) => prepare(name, map));
  loading.set(name, promise);
  return promise;
}

function prepare(name: string, map: FudeMap): LoadedMap {
  const out = lookup(map);
  loaded.set(name, out);
  return out;
}

const normalize = (value: unknown) => String(value).trim().toLowerCase();

/**
 * The lookup of a map's regions. The codes and the map's own names come
 * first; the other names of a region take only what nothing else has:
 * "Congo" is the Republic of the Congo, not its neighbour, whose other
 * names include it.
 */
export function lookup(map: FudeMap): LoadedMap {
  const index = new Map<string, number>();
  map.regions.forEach((region, i) => {
    for (const code of [...region.codes, region.name]) if (!index.has(normalize(code))) index.set(normalize(code), i);
  });
  map.regions.forEach((region, i) => {
    for (const name of region.names ?? []) if (!index.has(normalize(name))) index.set(normalize(name), i);
  });
  const paths: Path2D[] = [];
  return {
    map,
    find: (value) => (value === null || value === undefined ? undefined : index.get(normalize(value))),
    path: (i) => (paths[i] ??= new Path2D(map.regions[i]!.path)),
  };
}
