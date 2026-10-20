# 14. Export and import as a Cooklang recipe folder

- Status: accepted
- Date: 2026-10-20

## Context

Iteration 2 lets a household's owner export recipes and meals and import them,
to set up the family's meals quickly, keep a copy, or edit recipes in other
tools. Recipes are already Cooklang text (ADR 13). Meals (named groups of
recipes) have no Cooklang equivalent of their own, but Cooklang's conventions
define `.menu` files: valid Cooklang that uses sections to group recipe
references.

## Decision

An export is a zip of a Cooklang recipe folder:

- `recipes/<name>.cook` for each active recipe: the stored source with front
  matter setting `title` (the recipe's name) and `servings`. Other metadata
  is kept; `>> title/servings/serves` lines are dropped so they can't override
  the front matter when read back. Names become file names with characters
  unsafe in file names or Cooklang references replaced (and no `--` or `[`,
  which would start Cooklang comments in a reference), and ` (2)`... for
  repeats (ignoring case).
- `meals.menu`: front matter (`source: Mealplan`, `exported`), then a section
  per active meal with its recipes as references (`@./recipes/<name>{}`) in
  order; a meal without recipes is an empty section. Since iteration 3 a
  tagged meal's section starts with a `> Slots: Lunch, Dinner` note (a plain
  Cooklang note, so other tools show it), which imports match to our slots by
  name.

Imports read the same layout and plain Cooklang folders (iteration 2 design).

## Consequences

- No format of our own to document or version: exports open in CookCLI and the
  Cooklang apps, and other people's recipe folders import.
- File names are derived, so a recipe's name lives in `title`; a file renamed
  by hand keeps its title.
- `.menu` sections elsewhere often mean days, not meals; imports show them in
  the preview so the owner can leave them out.
- Archived recipes and meals, plans, slots and members are not exported (a
  meal's slot tags are, by slot name); the database backups cover full
  restores.
