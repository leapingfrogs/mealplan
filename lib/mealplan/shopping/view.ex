defmodule Mealplan.Shopping.View do
  @moduledoc """
  The shopping list as shown (`Mealplan.Shopping.view/1`):

    * `list` - the `ShoppingList` (its range)
    * `to_buy` - lines not ticked, as `%{line: %Line{}, more: %Quantity{} | nil}`;
      `more` is how much more is needed than when the line was ticked
    * `ticked` - lines ticked, as `%{line: %Line{}, more: nil}`
    * `staples` - lines left off as staples
    * `items` - manual items, in the order added
  """
  alias Mealplan.Shopping.Line

  @type entry :: %{line: Line.t(), more: Mealplan.Shopping.Quantity.t() | nil}
  @type t :: %__MODULE__{
          list: struct(),
          to_buy: [entry()],
          ticked: [entry()],
          staples: [Line.t()],
          items: [struct()]
        }

  defstruct [:list, to_buy: [], ticked: [], staples: [], items: []]
end
