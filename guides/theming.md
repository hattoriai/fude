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
| `--fude-sequential` | the ramp of a number's color, light to dark, as a list |
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
with the blade first among the series, and follows the Sumi themes, the
`data-theme` attribute, then the system's setting.

## Classes

`.fude`, `.fude-kind-<kind>` on each chart; `.fude-head`, `.fude-title`,
`.fude-subtitle`, `.fude-foot`, `.fude-caption`, `.fude-source`,
`.fude-legend`, `.fude-tooltip`, `.fude-data`, `.fude-panels`,
`.fude-panel`.
