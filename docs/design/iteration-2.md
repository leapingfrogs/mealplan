# Iteration 2: import and export

Lets the owner move a household's recipes and meals in and out of Mealplan, to
set up the family's meals quickly, keep a copy, or work on recipes in other
Cooklang tools. Inserted before shopping lists, which move to iteration 3.
Stories: [USER_STORIES.md](../../USER_STORIES.md), "Import and export".

## Scope

| In | Out (later, if wanted) |
|---|---|
| Export active recipes and meals as one zip | Plans, meal slots, members, households |
| Import a Mealplan export, `.cook` files, a `.menu`, or a zip of a recipe folder | Importing from recipe websites (URL scraping) |
| Preview with per-item choices; all-or-nothing apply | Archived recipes and meals in exports |
| Download one recipe as `.cook` | Scheduled or automatic backups of recipes (the database backups cover this) |
| Owner only | Members importing or exporting |

## The format: a Cooklang recipe folder

No new format: an export is what Cooklang tools (CookCLI, the apps) already
read, so it round-trips between households and opens elsewhere.

```text
mealplan-<household>-<YYYY-MM-DD>.zip
├── recipes/
│   ├── Chilli.cook
│   ├── Rice.cook
│   └── Rice (2).cook          two recipes may share a name
└── meals.menu
```

- **Recipes** are the stored Cooklang source with front matter carrying
  `title` (the recipe's name) and `servings`, set from the database; other
  metadata in the source is kept. Filenames are the name with characters that
  aren't safe in file names (`/ \ : * ? " < > |`, control characters)
  replaced by `-`, trimmed to 100 characters, with ` (2)`, ` (3)`... for
  repeats.
- **Meals** are one `meals.menu` (Cooklang's
  [menu convention](https://github.com/cooklang/spec/blob/main/conventions.md#menu-files)):
  a section per meal, its recipes as references in order. A meal with no
  recipes is a section with nothing in it.

  ```cooklang
  ---
  source: Mealplan
  exported: 2026-10-27
  ---
  = Chilli and rice

  @./recipes/Chilli{}
  @./recipes/Rice{}

  = Eat out
  ```

## Reading an import

Accepted uploads: one `.zip`, or any number of `.cook` and `.menu` files
together.

- **Every `.cook` file is a recipe**, wherever it is in the zip. Its name is
  the `title` metadata, else the filename without `.cook`; its servings the
  leading number of `servings` (or `serves`), else the household's usual
  number. The file's text becomes the recipe source as it is; parse warnings
  are shown in the preview but never block an import, as in the editor.
- **Every section of every `.menu` file is a meal**, named after the section.
  References (`@./path/name{}`) resolve to a recipe in the same import by its
  path (relative to the zip root, ignoring case and `.cook`), else to one of
  the household's active recipes with that name. Unresolved references are
  reported and left out. Quantities on references (scaling multipliers in
  Cooklang menus) are ignored, and so is other text in a section.
- **Ignored, and listed in the preview:** other files, hidden files and
  folders (`.x`, `__MACOSX`), and files that aren't valid UTF-8 or are too
  long.

## Matching and choices

Each imported recipe and meal is matched by name (ignoring case) against the
household's active ones and gets an action the owner can change in the
preview:

| Imported item | Default | Other choices |
|---|---|---|
| New name | **Add** | Leave out |
| Recipe with a name we have | **Skip** (keep ours) | Replace ours (source and servings; meals keep using it), Keep both (`Name (2)`) |
| Meal with a name we have | **Skip** | Replace ours (its recipes become the imported ones; history is kept), Keep both |

A meal's references follow the choices: a reference to a skipped recipe links
to ours, to a replaced or kept-both recipe to the imported one. Applying runs
in one transaction, rebuilds ingredient rows as a normal save does, and
broadcasts `{:recipe_changed, id}` / `{:meal_changed, id}` so open pages
update. The result says what was added, replaced and skipped.

## Limits and safety

Uploads are untrusted input from a logged-in owner.

- Upload at most 10 MB (LiveView `allow_upload`, `.zip`, `.cook`, `.menu`
  only; up to 200 files).
- Zips are read in memory with `:zip`, entries checked before extraction: at
  most 500 entries and 20 MB uncompressed in total (zip bombs), each recipe at
  most 50,000 characters (the editor's limit). Nothing is written to disk;
  entry paths are only used as keys, never as file paths, so `../` can't
  escape anywhere.
- Text must be valid UTF-8; names are trimmed and at most 120 characters.
- Imports are rate limited per household (5 an hour), like invitations.
- The export download is a controller route behind `:require_authenticated_user`
  that checks ownership, sent as an attachment with `Cache-Control: no-store`.

## Screens

- **Household page** (owner): an "Import and export" section with **Export
  recipes and meals** (downloads the zip) and **Import...** (an upload area
  accepting the files above).
- **Import preview** (`/household/import`): counts at the top ("12 recipes,
  4 meals: 9 new, 3 already here"); lists of recipes and meals, each with its
  action (a select on matches, a checkbox to leave out), parse warnings and
  unresolved references inline; problems with files at the bottom. **Import**
  applies; **Cancel** discards. Phone first, like the rest.
- **Recipe page:** **Download .cook** for the owner.

## Architecture

A new context, `Mealplan.Transfer`, with the parsing kept pure:

| Function | Does |
|---|---|
| `export(scope)` | `{filename, zip_binary}` of active recipes and `meals.menu` |
| `recipe_file(scope, recipe)` | `{filename, cook_text}` for one recipe |
| `read(uploads)` | Pure: files (name and binary) to a `%Bundle{recipes, meals, problems}`; never raises |
| `plan(scope, bundle)` | Matches against the household: an `%Import{}` of items with default actions |
| `apply(scope, import, choices)` | Applies in one transaction, broadcasts, returns a summary |

Front matter is rewritten by a small helper on the flat `key: value` subset
the parser reads (ADR 13), so other metadata survives.

## Tasks

1. **Format and export** — ADR 14 (Cooklang folder + `meals.menu`),
   `Transfer.export/1`, `recipe_file/2`, the download routes and buttons.
   Done when an export opens as expected (tests read it back with `:zip`).
2. **Reading imports** — `Transfer.read/1`: zips, `.cook`, `.menu`, limits and
   problems. Done when malformed and hostile inputs (zip bombs, bad UTF-8,
   deep paths, random bytes; property tests) give problems, never crashes.
3. **Matching and applying** — `plan/2` and `apply/3` with every choice, meal
   reference resolution and history. Done when export → import into a new
   household round-trips recipes, servings and meals exactly, and each choice
   is tested.
4. **Import screens** — the household section, upload, preview with choices,
   summary, rate limit; phone-checked.
5. **Release and deploy iteration 2** — docs, release, deploy, and import the
   family's recipes in production.

## Decisions to confirm

1. **Owner only**, as asked, including the single-recipe download (members
   could be allowed to download single recipes later).
2. **Matches are skipped by default**, so a re-import never overwrites edits
   without an explicit choice.
3. **Day sections in someone else's `.menu`** (`= Monday`) import as meals
   named "Monday"; the owner can leave them out in the preview. Mealplan's own
   exports only ever contain meals.
4. **Archived recipes and meals are left out** of exports.
