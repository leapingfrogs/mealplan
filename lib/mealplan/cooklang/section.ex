defmodule Mealplan.Cooklang.Section do
  @moduledoc "A part of a recipe (`= Dough`); the first may have no name."
  alias Mealplan.Cooklang.Note
  alias Mealplan.Cooklang.Step

  @type t :: %__MODULE__{name: String.t() | nil, blocks: [Step.t() | Note.t()]}
  defstruct name: nil, blocks: []
end
