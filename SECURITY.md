# Security

## Reporting a vulnerability

Do not open a public issue for a security problem. Report it privately
through GitHub: [Report a vulnerability](https://github.com/hattoriai/fude/security/advisories/new).

Say what an attacker can do, and how: the chart, the spec, the data or
the event, and the steps or the payload. We answer within a week, agree
on a fix and a date, and credit you in the advisory unless you ask us
not to.

## Supported versions

Security fixes are made to the latest release. Fude is before 1.0, so a
fix is not backported to an earlier minor version.

## What is in scope

A chart's spec may come from a person or an agent (`Fude.Spec.load/1`
of a saved chart), its data from anyone who writes to your database, and
its words from both. A problem is in scope when such a spec, data or
words can:

- run script in the page: through a title, a label, a note, a category,
  a region's name, a tooltip or a format;
- make `Fude.Spec.load/1` create atoms, crash the process that loads it,
  or make the server do unbounded work (too many bins, layers, panels or
  units of time);
- make `Fude.query/3` run SQL other than the grouping of the query it
  was given: a field name, a unit of time or a bin reaching the SQL as
  text;
- make the browser do unbounded work from a spec or an appended row.

What a person may see is decided by the app: the rows of a query and the
fields of the data are the app's to filter, and a chart draws what it is
given.
