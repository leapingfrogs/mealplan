defmodule Mealplan.Transfer.ImportedMeal do
  @moduledoc """
  A meal read from a `.menu` section. Each reference is either
  `{:path, "recipes/chilli"}` (from `@./recipes/Chilli{}`, lower-case,
  without `.cook`) or `{:name, "Chilli"}` (a plain `@Chilli{}`), in order.
  `slot_names` come from the section's first `> Slots: Lunch, Dinner` note.
  """
  @type recipe_ref :: {:path, String.t()} | {:name, String.t()}
  @type t :: %__MODULE__{
          file: String.t(),
          name: String.t(),
          references: [recipe_ref()],
          slot_names: [String.t()]
        }

  defstruct [:file, :name, references: [], slot_names: []]
end
