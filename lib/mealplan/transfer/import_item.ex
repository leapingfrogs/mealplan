defmodule Mealplan.Transfer.ImportItem do
  @moduledoc """
  One recipe or meal in an import.

    * `key` - stable id for the preview's choices (`recipe-3`, `meal-0`)
    * `imported` - the `ImportedRecipe` or `ImportedMeal`
    * `existing` - the household's active recipe or meal with the same name
    * `action` - `:add` or `:leave_out` when new; `:skip`, `:replace`,
      `:keep_both` or `:leave_out` when it matches one we have
    * `servings` - for recipes: from the file, else the household's usual
      number, within 1..100
    * `references` - for meals, in order: `{:imported, recipe_key}`,
      `{:existing, recipe}` or `{:missing, label}`
    * `slot_ids` - for meals: the household's slots to tag it with, matched
      from its `slot_names` and then as the owner chooses
    * `unmatched_slots` - for meals: slot names that match none of ours
  """
  @type action :: :add | :skip | :replace | :keep_both | :leave_out
  @type t :: %__MODULE__{
          key: String.t(),
          imported: struct(),
          existing: struct() | nil,
          action: action(),
          servings: pos_integer() | nil,
          references: list(),
          slot_ids: [Ecto.UUID.t()],
          unmatched_slots: [String.t()]
        }

  defstruct [
    :key,
    :imported,
    :existing,
    :action,
    :servings,
    references: [],
    slot_ids: [],
    unmatched_slots: []
  ]

  @doc "The actions open to an item."
  def actions(%__MODULE__{existing: nil}), do: [:add, :leave_out]
  def actions(%__MODULE__{}), do: [:skip, :replace, :keep_both, :leave_out]
end
