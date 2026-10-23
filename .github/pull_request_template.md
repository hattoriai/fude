## Why

<!-- The problem this solves, for whom, and what happened before it (an error, a wrong mark, a chart that would not draw). -->

Fixes #<!-- the issue; see CONTRIBUTING.md for when a pull request needs one -->

## What

<!-- The change, in a few lines. A screenshot, in light and dark, for a change to the look. -->

## How it was tested

<!-- The tests added, and what you ran by hand (the browsers, locales and databases). -->

## Checklist

- [ ] One change: anything unrelated is in its own pull request.
- [ ] A bug fix has a test that fails on `main` and passes here.
- [ ] `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, `mix docs`, `mix test` and `mix dialyzer` pass.
- [ ] `FUDE_DB=postgres mix test` and `FUDE_DB=mysql mix test` pass, for a change to `Fude.Query`.
- [ ] `npm run typecheck` (in `assets/`) and `mix test.js` pass, for a change to `assets/`.
- [ ] `mix test.e2e` passes, for a change the browser sees.
- [ ] Specs saved before this change still load (a migration in `Fude.Spec`), for a change to the spec.
- [ ] The guides and the `[Unreleased]` section of `CHANGELOG.md` are updated, for a change a user can see.
- [ ] Says so here if it changes the public API, the spec or what a chart does today.
- [ ] No changes to the version (the maintainers keep it).
