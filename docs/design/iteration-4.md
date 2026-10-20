# Iteration 4: shopping lists

Turn the planned meals for a stretch of days into one shared shopping list:
ingredients scaled to what will actually be cooked, merged across recipes,
with staples left off, room for things that aren't in any recipe, and ticks
that every member sees live while shopping. Stories:
[USER_STORIES.md](../../USER_STORIES.md), "Shopping lists". The data model and
servings maths were set out in [iteration 1](iteration-1.md) ("Cooked servings
and leftovers"); this builds on them.

## Scope

| In | Out (later, if wanted) |
|---|---|
| One current list per household, for a date range (default: the rest of the planning week) | Several lists at once, list history |
| Scale to cooked servings (leftovers counted in their source); merge by ingredient | Aisles or shop sections, custom ordering |
| Convert within metric mass (mg, g, kg) and volume (ml, cl, dl, l) | Converting between cups, spoons, ounces and metric; mass ↔ volume |
| Household staples left off, shown collapsed | Pantry stock levels |
| Manual items | Sharing to other apps (beyond copying as text) |
| Live ticking for every member; the list follows plan changes, keeping ticks and manual items | Prices, online ordering |
| Copy the list as text | |

## The list

The list isn't a stored copy of the plan. What to buy is **computed** from the
plan whenever the list is shown, so it always matches the current plan; only
what the household does to it is stored: the range, ticks, manual items and
staples.

### What's needed

For each planned meal dated in the range, for each recipe the meal had on that
date (`Meals.recipes_on/3`, so a later edit to the meal doesn't rewrite an old
plan) that isn't eaten there as leftovers:

```text
cooked = planned servings + Σ servings of later meals eating it as leftovers
scale  = cooked ÷ recipe servings
```

Each ingredient row of the recipe contributes `quantity × scale` (or its
quantity unscaled when it isn't `scalable`). Leftover recipes contribute
nothing: their servings are cooked, and shopped for, with their source, even
when the source falls in an earlier range. A source in the range whose
leftovers are eaten after it still counts them. Meals without recipes, skips
and recipes without ingredients add nothing.

### Merging and units

Rows merge by ingredient `key` (normalised name: lower-case, singular) and
then by unit:

- **Metric mass** (mg, g, kg) adds up as grams, **metric volume** (ml, cl, dl,
  l) as millilitres, and each is shown in the larger unit from 1000 up
  (`1.2 kg`, `750 ml`).
- **Other units** (tsp, tbsp, cup, oz, lb, pint, or a unit we don't know) add
  up only with the same unit.
- **Counts** (no unit, or item/piece/whole) add up as a number.
- **Text quantities** ("a handful") and ingredients with no quantity are
  listed as written, once each ("some").

An ingredient needed in more than one way is one line with its parts:
`Olive oil: 2 tbsp + 150 ml`. Numbers are shown to at most two decimal places
without trailing zeros; counts are rounded up to a whole number
(`1.5 onions` → `2 onions`). Optional ingredients (`@?`) are listed, marked
optional. Each line shows the name as written in the first recipe, and opens to
show where it comes from: `Chilli · Mon dinner · 400 g`.

### Staples

A household keeps a list of **staples**: ingredient keys it always has (salt,
pepper, olive oil). Staples are left off the list and shown at the bottom as
a collapsed "Staples, not listed (N)" group, so they're one tap away if
something has run out. Any line has **Always have this** to make it a staple;
staples are removed from the same group or a small staples page. Any member
can manage staples.

### Manual items

Free text with an optional quantity ("Kitchen roll", "Milk 2 l"), added by any
member. They aren't merged with recipe ingredients and stay on the list until
removed or the list is cleared.

### Ticking

Ticking a line records its key and the amount it showed. Ticked lines move to
the bottom, struck through, for every member at once (PubSub, as elsewhere).

When the plan changes, the list recomputes:

- A ticked line whose amount is **the same or less** stays ticked.
- A ticked line whose amount **grows** comes back unticked, showing the
  extra: `Chopped tomatoes: 3 tins (1 more since ticked)`.
- A ticked line no longer needed disappears; its tick is forgotten.

### The range and starting again

The list covers a date range, at most 14 days. It starts as **today to the
end of the planning week** (the week the planner opens on: this week, or next
week once this one is fully planned). Changing the range keeps ticks and
manual items. **Start a new list** (after confirming) clears ticks and
checked-off manual items, keeps unticked manual items, and resets the range
to the default.

**Copy as text** puts the unticked lines on the clipboard, one per line, for
pasting into a message.

## Data

All rows carry `household_id` with composite foreign keys, as elsewhere.

| Table | Fields | Notes |
|---|---|---|
| `shopping_lists` | `household_id` (unique), `starts_on`, `ends_on` | One per household, created on first visit |
| `shopping_ticks` | `shopping_list_id`, `key`, `amount` (text) | Unique per list and key; `amount` is the line as ticked, for the "more since ticked" rule |
| `shopping_items` | `shopping_list_id`, `text`, `ticked_at`, `position` | Manual items |
| `staples` | `household_id`, `key`, `name` | Unique per household and key |

Changes broadcast `{:shopping_changed, household_id}`; plan, recipe and meal
changes already broadcast, and the shopping page recomputes on them.

## Screens

- **Shopping** (`/shopping`), a fifth tab: the range at the top (tap to
  change, with "This week" and "Next week" shortcuts), then:
  1. **To buy**: lines alphabetically, each with a tick box, its amount, and a
     chevron that opens where it's from, **Always have this**, and nothing
     else.
  2. **Add an item** field.
  3. **Ticked (N)**, collapsed once there are more than a few.
  4. **Staples, not listed (N)**, collapsed.

  A menu holds **Copy as text**, **Staples** and **Start a new list**. An empty
  range says so and links to the plan.
- **Staples** (`/shopping/staples`): the household's staples with remove, and
  an add field (normalised the same way as ingredients).

Phone first; ticking must be a large target and work one-handed.

## Architecture

| Where | Adds |
|---|---|
| `Shopping` (new context) | `get_list/1`, `needs(scope, list)` (the computed lines), `set_range/3`, `tick/3`, `untick/3`, manual items, staples, `start_new/1`; broadcasts |
| `Shopping.Quantity` | merging, metric conversion and formatting: pure, property-tested |
| `Planning` | the cooked-servings maths for a range, shared with `leftover_sources` |
| `ShoppingLive.Index`, `ShoppingLive.Staples` | the screens, in the `:require_household` live session |

`needs` reads the plan, meals, leftovers and ingredient rows for the range in
a handful of queries and merges in Elixir; at a family's scale (tens of
recipes a week) that's milliseconds, and keeps the maths testable without the
database.

## Tasks

1. **Shopping maths** — what's needed for a range: cooked servings from the
   plan (leftovers in their source), recipes as on the planned date, scaling,
   merging by key and unit, metric conversion, formatting and rounding,
   optional marking, where each line comes from. Done when the iteration 1
   examples and merging/conversion cases are covered by tests, with property
   tests for `Shopping.Quantity`.
2. **Lists, ticks and staples** — migrations and the `Shopping` context: the
   household's list and range, ticks with the "more since ticked" rule, manual
   items, staples, starting a new list, broadcasts. Done when ticks and manual
   items survive plan changes as described (tests).
3. **Shopping screen** — the tab, range picker, lines with live ticking, where
   each line is from, manual items, the ticked and staples groups, copy as
   text, start a new list, and the staples page. Done when it works on a phone
   with two members ticking at once (tests and a 390 px check).
4. **Release and deploy iteration 4** — docs, release, deploy, shop from a list
   for real.

## Decisions to confirm

1. **One current list per household**, computed from the plan rather than
   stored, with only ticks, manual items, range and staples kept. No list
   history.
2. **The default range is today to the end of the planning week**, adjustable
   up to 14 days.
3. **Conversions stay within metric mass and metric volume.** Spoons, cups,
   ounces and pounds merge only with themselves, shown side by side
   (`2 tbsp + 150 ml`).
4. **Counts round up** to whole numbers; everything else shows up to two
   decimal places.
5. **A ticked line whose amount grows comes back unticked**, showing the
   extra; one that shrinks stays ticked.
6. **Staples are household-wide**, managed by any member, matched by
   ingredient key, and shown collapsed rather than hidden.
7. **Optional ingredients are listed**, marked optional.
8. **Starting a new list keeps unticked manual items** and clears the rest.
