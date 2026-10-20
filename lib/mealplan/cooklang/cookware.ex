defmodule Mealplan.Cooklang.Cookware do
  @moduledoc "A piece of equipment (`#frying pan{}`); `quantity` is nil when not given."
  @type t :: %__MODULE__{
          name: String.t(),
          quantity: Decimal.t() | String.t() | nil,
          optional: boolean()
        }
  defstruct name: "", quantity: nil, optional: false
end
