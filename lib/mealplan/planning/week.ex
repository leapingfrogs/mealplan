defmodule Mealplan.Planning.Week do
  @moduledoc """
  A household's plan for one Monday-to-Sunday week: its days, the active
  slots, the planned meals (with meals, recipes and leftovers loaded) and
  skips, and how much of it is planned.

  `retired_slots` are archived slots that this week's planned meals still
  use, so past weeks keep showing them. `planned` counts the day-and-slot cells that have a meal or a skip, out of
  `cells` (days × active slots).
  """
  alias Mealplan.Households.MealSlot
  alias Mealplan.Planning.PlannedMeal
  alias Mealplan.Planning.SlotSkip

  @type t :: %__MODULE__{
          start: Date.t(),
          days: [Date.t()],
          slots: [%MealSlot{}],
          retired_slots: [%MealSlot{}],
          planned_meals: [%PlannedMeal{}],
          skips: [%SlotSkip{}],
          planned: non_neg_integer(),
          cells: non_neg_integer()
        }

  defstruct [
    :start,
    days: [],
    slots: [],
    retired_slots: [],
    planned_meals: [],
    skips: [],
    planned: 0,
    cells: 0
  ]

  @doc "True when every cell has a meal or a skip (and there is at least one slot)."
  def fully_planned?(%__MODULE__{planned: planned, cells: cells}),
    do: cells > 0 and planned == cells
end
