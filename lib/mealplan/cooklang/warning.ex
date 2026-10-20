defmodule Mealplan.Cooklang.Warning do
  @moduledoc "Something in the text that was ignored or read loosely."
  @type t :: %__MODULE__{line: pos_integer() | nil, message: String.t()}
  defstruct line: nil, message: ""
end
