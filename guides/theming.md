# Theming

Every color, space and font of a chart comes from a `--fude-*` custom
property. The defaults have no specificity: a value set on `:root`, on an
ancestor or on `.fude` wins.

| Property | Is |
| --- | --- |
| `--fude-font`, `--fude-font-size` | the type of the chart's words |
| `--fude-text`, `--fude-secondary`, `--fude-muted` | the words: titles and values, subtitles and labels, axes |
| `--fude-surface` | the paper under the chart: the gaps between marks and the rings of points |
| `--fude-grid`, `--fude-baseline` | the hairline grid, and the line at zero |
| `--fude-series-1` to `--fude-series-8` | the colors of the series, in order |
| `--fude-sequential` | the ramp of a number's color, light to dark, as a list (the scheme `:blue`); or `accent`, a ramp of `--fude-accent` from the surface to the text |
| `--fude-scheme-green`, `-orange`, `-purple`, `-gray`, `-viridis`, `-red-blue`, `-red-green` | the named schemes of a color channel, each a list |
| `--fude-scheme-okabe-ito-1` to `-8` | the scheme `:okabe_ito`, in order |
| `--fude-increase`, `--fude-decrease`, `--fude-total` | a waterfall's bars |
| `--fude-map-empty` | a region of a map with no value |
| `--fude-bar-max`, `--fude-bar-radius`, `--fude-gap`, `--fude-line` | the thickest bar, its round end, the gap between marks, a line's width |
| `--fude-duration` | how long marks move, in milliseconds |
| `--fude-tooltip-background`, `--fude-tooltip-text`, `--fude-tooltip-border`, `--fude-shadow` | the tooltip |
| `--fude-radius`, `--fude-focus-ring` | corners, and the ring of the focused chart |

## The colors of the series

The eight colors are a categorical order checked for color vision
deficiencies: each is told apart from the next by people with the
common ones, and the first three from each other. Keep the order when you
change them; a chart of more than eight series is clearer as small
multiples, or with the rest as "Other".

Text never wears a series' color: values and labels are in the text's
colors, beside a mark of the series' color.

## Dark mode

Dark follows the app's own switch, `.dark` or `[data-theme="dark"]` on an
ancestor, so that a light app stays light. The dark colors are their own
steps for the dark paper, not the light ones inverted; the sequential
ramp starts dark there, so that low values recede.

## The Sumi theme

Load `fude-sumi.css` after `fude.css`. It maps every property to the
Sumi tokens of the page (or the `--sumi-*` names, or Sumi's own palette),
with the theme's accent first among the series, and follows the Sumi
themes, the `data-theme` attribute, then the system's setting.

Each of Sumi's seven themes (Ink, Smoke, Stone and Lacquer; Paper, Snow
and Silk) has its own accent, and the charts follow it:

* the first series is the accent, and a series of the accent's hue
  (Snow's indigo and the blue, Smoke's jade and the green, Stone's gold
  and the amber, Silk's pink and the pink) is orange instead, so that no
  two series look alike;
* the sequential ramp is the accent's (`--fude-sequential: accent`):
  from faint on the page, through the accent, to near the text, so that
  low values recede on a light theme and on a dark one;
* the dark themes have the dark palette.

The development app (`mix dev`) shows the gallery in each:
`?sumi=smoke`, or the links under its menu.

## Classes

`.fude`, `.fude-kind-<kind>` on each chart; `.fude-head`, `.fude-title`,
`.fude-subtitle`, `.fude-foot`, `.fude-caption`, `.fude-source`,
`.fude-legend`, `.fude-tooltip`, `.fude-data`, `.fude-panels`,
`.fude-panel`; with `table={:swap}`, `.fude-frame`, `.fude-data-over`
and `.fude-data-toggle`, and `[data-fude-data]` on the chart while its
table shows.
