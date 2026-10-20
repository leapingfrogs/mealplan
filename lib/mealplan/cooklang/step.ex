defmodule Mealplan.Cooklang.Step do
  @moduledoc "One paragraph of the method: text interleaved with components."
  alias Mealplan.Cooklang.Cookware
  alias Mealplan.Cooklang.Ingredient
  alias Mealplan.Cooklang.Text
  alias Mealplan.Cooklang.Timer

  @type item :: Text.t() | Ingredient.t() | Cookware.t() | Timer.t()
  @type t :: %__MODULE__{items: [item()]}
  defstruct items: []
end
