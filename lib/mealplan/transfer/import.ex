defmodule Mealplan.Transfer.Import do
  @moduledoc """
  An import matched against the household (`Mealplan.Transfer.plan/2`):
  each recipe and meal with its match and action, and the problems read
  from the files. The owner adjusts actions in the preview, then
  `Mealplan.Transfer.apply/3` carries it out.
  """
  alias Mealplan.Transfer.ImportItem

  @type t :: %__MODULE__{
          recipes: [ImportItem.t()],
          meals: [ImportItem.t()],
          problems: [Mealplan.Transfer.Bundle.problem()]
        }

  defstruct recipes: [], meals: [], problems: []
end
