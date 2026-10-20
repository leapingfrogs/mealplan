defmodule Mealplan.Cooklang.Timer do
  @moduledoc "A timer (`~eggs{3%minutes}`); the name is optional."
  @type t :: %__MODULE__{
          name: String.t() | nil,
          quantity: Decimal.t() | String.t() | nil,
          unit: String.t() | nil
        }
  defstruct name: nil, quantity: nil, unit: nil
end
