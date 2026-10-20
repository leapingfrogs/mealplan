defmodule Mealplan.Transfer.Bundle do
  @moduledoc """
  What an import contains, read from the uploaded files before anything
  touches the database: recipes, meals and problems with the files.
  """
  alias Mealplan.Transfer.ImportedMeal
  alias Mealplan.Transfer.ImportedRecipe

  @type problem :: %{file: String.t(), message: String.t()}
  @type t :: %__MODULE__{
          recipes: [ImportedRecipe.t()],
          meals: [ImportedMeal.t()],
          problems: [problem()]
        }

  defstruct recipes: [], meals: [], problems: []
end
