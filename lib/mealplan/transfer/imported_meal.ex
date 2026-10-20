defmodule Mealplan.Transfer.ImportedMeal do
  @moduledoc """
  A meal read from a `.menu` section. Each reference is either
  `{:path, "recipes/chilli"}` (from `@./recipes/Chilli{}`, lower-case,
  without `.cook`) or `{:name, "Chilli"}` (a plain `@Chilli{}`), in order.
  """
  @type recipe_ref :: {:path, String.t()} | {:name, String.t()}
  @type t :: %__MODULE__{file: String.t(), name: String.t(), references: [recipe_ref()]}

  defstruct [:file, :name, references: []]
end
