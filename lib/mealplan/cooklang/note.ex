defmodule Mealplan.Cooklang.Note do
  @moduledoc "Background text written on lines starting with `>`."
  @type t :: %__MODULE__{text: String.t()}
  defstruct text: ""
end
