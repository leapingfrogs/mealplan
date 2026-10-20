defmodule Mealplan.Cooklang.Recipe do
  @moduledoc """
  The result of parsing Cooklang text.

  `ingredients`, `cookware` and `timers` list every occurrence in the order
  written; the same items also appear inside the steps. `servings` is the
  leading number of the `servings` (or `serves`) metadata, if any.
  """
  alias Mealplan.Cooklang.Cookware
  alias Mealplan.Cooklang.Ingredient
  alias Mealplan.Cooklang.Section
  alias Mealplan.Cooklang.Timer
  alias Mealplan.Cooklang.Warning

  @type metadata_value :: String.t() | [String.t()]

  @type t :: %__MODULE__{
          metadata: %{String.t() => metadata_value()},
          servings: pos_integer() | nil,
          sections: [Section.t()],
          ingredients: [Ingredient.t()],
          cookware: [Cookware.t()],
          timers: [Timer.t()],
          warnings: [Warning.t()]
        }

  defstruct metadata: %{},
            servings: nil,
            sections: [],
            ingredients: [],
            cookware: [],
            timers: [],
            warnings: []
end
