defmodule Mealplan.Shopping.Line do
  @moduledoc """
  One ingredient on the shopping list: every recipe row with the same `key`,
  merged. `name` is as written in the first recipe that needs it; `amount`
  is the `quantity` as shown. `optional` when every row is optional.

  `sources` say where it comes from, in plan order: one per recipe cooked in
  a planned meal, `%{planned_meal: %PlannedMeal{}, recipe: %Recipe{},
  quantity: %Quantity{}, amount: "400 g"}` (the planned meal has its slot
  loaded).
  """
  alias Mealplan.Shopping.Quantity

  @type source :: %{
          planned_meal: struct(),
          recipe: struct(),
          quantity: Quantity.t(),
          amount: String.t()
        }
  @type t :: %__MODULE__{
          key: String.t(),
          name: String.t(),
          quantity: Quantity.t(),
          amount: String.t(),
          optional: boolean(),
          sources: [source()]
        }

  defstruct [:key, :name, :quantity, :amount, optional: false, sources: []]
end
