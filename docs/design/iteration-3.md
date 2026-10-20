# Iteration 3: meal slot tags

Tag meals with the slots they suit, so planning a slot offers the right meals
first, and carry the tags through export and import. Inserted before shopping
lists, which move to iteration 4. Stories:
[USER_STORIES.md](../../USER_STORIES.md), "Meal slot tags".

## Scope

| In | Out (later, if wanted) |
|---|---|
| Tag meals with any number of the household's slots, on the meal page | Tagging recipes (planning a recipe goes through its one-recipe meal) |
| The add sheet lists meals tagged for the slot first; other meals and recipes start collapsed | Free-form tags (cuisine, quick, vegetarian) |
| Tags in exports; matched, chosen or bulk-set on import | Suggesting tags automatically from past plans |

## Data

`meal_slot_tags (household_id, meal_id, meal_slot_id)`: composite foreign keys
to `meals` and `meal_slots` on `household_id`, as elsewhere, so a tag can't
cross households. Unique per meal and slot. Deleting a meal deletes its tags;
deleting a slot outright deletes its tags; **archiving** a slot keeps them
(history) but archived slots aren't shown or offered as tags. Any member can
tag, as any member can edit meals; changes broadcast `{:meal_changed, id}`.

## Screens

- **Meal page** (`/meals/:id`): a "Suits" row of the household's active slots
  as toggle chips; tapping one tags or untags the meal. The meal list shows each
  meal's tags under its name.
- **Add to a slot** (week plan sheet), Meals tab, top to bottom:
  1. **Meals for <slot>**: meals tagged with this slot, open.
  2. **Other meals (N)**: every other active meal (untagged or tagged for other
     slots), collapsed.
  3. **Recipes (N)**: collapsed.

  Searching filters all three and opens any section with matches; matching
  meals for the slot still come first. Planning a meal from the sheet (an existing
  meal, **New meal "…"**, or a recipe directly, through its one-recipe meal)
  adds this slot to the meal's tags if it isn't there, and so does changing a
  planned meal to another; untagged meals pick up tags as they're planned, so
  the list learns from planning. Tags are only added this way, never removed,
  and a past plan in an archived slot adds none. The Leftovers tab is unchanged.

## Export and import

Cooklang has no per-section metadata, but notes (`> ...`) are valid Cooklang
and other tools display them, so a meal's tags are a note at the top of its
section in `meals.menu`:

```cooklang
= Chilli night

> Slots: Lunch, Dinner

@./recipes/Chilli{}
```

- **Export** writes the note for meals with tags (active slots, in slot
  order); untagged meals have none.
- **Reading** takes the first note in a meal's section that starts with
  `Slots:` (ignoring case) and splits it on commas; other notes are ignored.
- **Matching:** each name matches one of the household's active slots,
  ignoring case and surrounding spaces. Names that match nothing are kept and
  shown.
- **Preview:** each meal shows its slot tags as toggle chips, matched ones
  selected, with unmatched names listed beside them ("Brunch: no such
  slot"). A **Set slots for meals without any** control at the top applies a
  chosen set of slots to every imported meal that has none, which the owner can
  then adjust per meal.
- **Applying:** Add and Keep both tag the new meal with the chosen slots;
  Replace sets our meal's tags to them; Skip and Leave out don't touch tags.

## Architecture

| Where | Adds |
|---|---|
| `Meals` | `set_slots(scope, meal_id, slot_ids)`, `list_meals/2` and `get_meal!/2` load `slots` (active, in order), `meals_for_slot/2` |
| `Planning` | `plan_meal` and `plan_recipe` take `tag: true` from the sheet to tag the meal with the slot |
| `Transfer` | the `> Slots:` note in export and reading; `ImportedMeal.slot_names`; `ImportItem.slot_ids` (chosen) and `unmatched_slots`; applying tags |

## Tasks

1. **Meal slot tags** — migration, `Meals.set_slots/3`, tags loaded with meals,
   the meal page chips and list display. Done when tags persist, are scoped to
   the household, and follow slot archive and delete (tests).
2. **Planning with tags** — the add sheet's three sections (meals for the slot
   open; other meals and recipes collapsed), search across them, tagging from
   the sheet. Done when the sheet works on a phone and tests cover ordering,
   collapsing and tagging.
3. **Tags in export and import** — the menu note, reading, matching, preview
   chips and the bulk control, applying. Done when export → import round-trips
   tags exactly and untagged and unmatched meals can be tagged in the preview
   (tests).
4. **Release and deploy iteration 3** — docs, release, deploy, tag the family's
   meals.

## Decisions to confirm

1. **Nothing is hidden:** the sheet shows matching meals first and the rest
   collapsed, rather than filtering other meals out entirely. Until meals are
   tagged (all existing ones), "Meals for <slot>" is empty and the sheet says
   so, with other meals one tap away.
2. **Planning from the sheet tags the meal** with that slot, if it isn't
   already: new meals, recipes planned directly and existing meals alike
   (changed after review, so untagged meals pick up tags through planning).
3. **The export format** is a `> Slots: Lunch, Dinner` note in each meal's
   section.
4. **Any member can tag meals**, like other meal edits.
5. **Bulk "set slots for meals without any"** in the import preview, as well as
   per-meal choices.
