defmodule Mealplan.Cooklang.Text do
  @moduledoc "Plain text within a step."
  @type t :: %__MODULE__{value: String.t()}
  defstruct value: ""
end
