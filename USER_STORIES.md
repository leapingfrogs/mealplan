# User Stories

As a user without an associated household I am prompted to create my Household by giving it a name and optionally inviting other users to the household by email.

As the user that creates a household I am designated as the owne of that household and have the option to rename it and add/remove members from the household.

As a user invited to a household, upon first login I am linked to the household and can view its properties.
- When a user is removed from the household they are no longer linked to a household so will receive the prompt to create one

As a user within a household I am able to create a named Recipe, recipies are created using a markup language such as cookmark.

A recipe can exist as just a name and serving size, the steps and ingredients can be added later.

As a user within a household I am able to create a Meal.

As a user within a household I am able to link and unlink existing recipes to a Meal.

As a user within a household with meals I am able to create a PlannedMeal linking a meal to a MealSlot and date.

A MealSlot is a named time of eating for a household, the defaults are Breakfast, Lunch, Dinner, Snack.

The owner of a household may create and edit custom meal slots and set their order within a day.

Meal Planning is an activity of assigning meals to mealslots for dates within a given week, it defaults to the current or upcoming week depending upon whether meals are already fully planned. It is valid to mark a MealSlot as skipped for a given day when planning. There should be a UI to simplify this.

As a user with a defined set of meals for a week they should be able to create a shopping list from the required ingredients.

---

## Editing and deleting

Something "in use by past plans" is part of the household's meal history. Rather than being deleted, it is archived: hidden from lists and pickers, but still shown in past plans. Anything never used in a plan is deleted outright.

### Recipes

As a user within a household I am able to edit a recipe's name, serving size and Cooklang source, and see the parsed ingredients and steps update as I edit.

As a user within a household I am able to delete a recipe after confirming. If the recipe is part of any meals, the confirmation lists them and the recipe is removed from those meals; if it appears in past plans it is archived instead of deleted.

As a user within a household I am able to view archived recipes and restore one, so it appears in lists and pickers again.

### Meals

As a user within a household I am able to rename a meal.

As a user within a household I am able to delete a meal after confirming. If the meal is planned on today or a future date, the confirmation lists those dates and the planned meals are removed; if it appears in past plans it is archived instead of deleted.

As a user within a household I am able to view archived meals and restore one.

### Planned meals

As a user within a household I am able to change which meal a planned meal uses, and the number of servings it is planned for.

As a user within a household I am able to move a planned meal to a different date or meal slot.

As a user within a household I am able to remove a planned meal; the slot becomes unplanned again.

As a user within a household I am able to undo marking a meal slot as skipped for a day.

### Meal slots

As the owner of a household I am able to rename a meal slot; meals already planned in it stay planned in it.

As the owner of a household I am able to delete a meal slot. If meals are planned in it on today or a future date, I must first choose another slot to move them to, or confirm they are removed. Past planned meals keep showing the slot's name in history.

As the owner of a household I am able to restore the default meal slots (Breakfast, Lunch, Dinner, Snack) without affecting any custom slots.

## Households (agreed during review)

A user belongs to at most one household.

As the owner of a household I can see pending invitations and revoke them; an invitation expires after 7 days if it hasn't been accepted.

As a user who already belongs to a household and is invited to another, I see the pending invitation and can accept it only after leaving my current household.

As a member of a household (not the owner) I am able to leave it; I then receive the prompt to create a household.

As the owner of a household I am able to transfer ownership to another member, and must do so before I can leave.

As the owner of a household I am able to delete it after confirming by typing its name; all of its recipes, meals, slots and plans are deleted and its members receive the prompt to create a household.

All members of a household can create and edit recipes, meals and plans; managing members and meal slots is reserved for the owner.

## Planning (agreed during review)

A household has a "usually feeding" number of people, asked for when it is created and editable by the owner. A planned meal records how many servings it is for, defaulting to that number; the shopping list scales ingredient quantities to the planned servings.

As a user planning a week I am able to mark a planned meal, or one recipe within it, as leftovers from an earlier planned meal up to 14 days before (so a batch cooked or frozen at the weekend can feed meals the following week), with its own number of servings. One cooked meal can feed several later meals. The earlier meal is then cooked for its planned servings plus all leftover servings taken from it, and the shopping list scales its ingredients to that total (for a recipe that serves 4: planned for 4 with 2 leftover servings means cooking 6; planned for 2 with 2 leftover servings means cooking the recipe's 4). Leftovers themselves add nothing else to the shopping list.

A meal may have no recipes (for example "Eat out" or "Leftovers"), and a single recipe can be planned directly, which creates a meal containing just that recipe.

More than one meal can be planned in the same slot on the same day.

Meal planning weeks start on Monday. A week is fully planned when every meal slot on every day has at least one planned meal or is marked as skipped.

