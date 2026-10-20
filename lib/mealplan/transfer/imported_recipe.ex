defmodule Mealplan.Transfer.ImportedRecipe do
  @moduledoc """
  A recipe read from an import. `path` identifies it for menu references:
  its path in the upload, lower-case, without `.cook` (`recipes/chilli`).
  `servings` is nil when the file doesn't say; `warnings` are the parser's.
  """
  @type t :: %__MODULE__{
          file: String.t(),
          path: String.t(),
          name: String.t(),
          servings: pos_integer() | nil,
          source: String.t(),
          warnings: [Mealplan.Cooklang.Warning.t()]
        }

  defstruct [:file, :path, :name, :servings, source: "", warnings: []]
end
