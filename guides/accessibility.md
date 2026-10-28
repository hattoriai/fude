# Accessibility

What a person who does not see the chart gets, and what one who does not
use a mouse can do.

* **A description.** The chart's plot has an accessible name: its own
  `description`, or one that Fude writes from the chart (its kind, what
  each axis shows and its range, the series).
* **The keyboard.** The chart is one tab stop. The arrows move through
  the data: along the x of a line or an area (Up and Down move between
  its series), from mark to mark on the others. Home and End go to the
  ends, Escape leaves. Each step shows its tooltip and a live region says
  it ("May 2026. Online: €75,912"). On a chart with a `brush`, Shift and
  the arrows choose a range from where the keyboard is, Enter zooms to it
  or sends it, and Escape goes back.
* **A table.** Under each chart, a toggle opens a table of its data, as
  the chart draws it (summed, in bins). It is on the page before the
  hook mounts, and with JavaScript off. With `table={:swap}`, a **Data**
  button (`aria-pressed`, and `aria-controls` the table) shows it in the
  plot's place, a region that the keyboard scrolls.
* **Single numbers** are HTML: a `progressbar` and a `meter` with their
  values.
* **Colors.** The series' colors are told apart by people with the
  common color vision deficiencies, and a legend names every series of
  two or more. Text has the contrast of text, never a series' color.
* **Motion.** With reduced motion, marks go to their places at once.
* **Forced colors.** The focus ring and the tooltip keep their lines.
