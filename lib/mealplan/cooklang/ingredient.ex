defmodule Mealplan.Cooklang.Ingredient do
  @moduledoc """
  An ingredient as written (`@flour{250%g}(sifted)`), plus the normalised
  fields used to merge and scale ingredients:

    * `quantity` - a `Decimal` for numbers and fractions, the text as written
      for anything else ("few"), or `nil` when none was given ("some")
    * `key` - the name lower-cased, trimmed and singular, for merging
    * `canonical_unit` - the unit's standard spelling (`"g"` for "grams"),
      `nil` for counted items
    * `dimension` - `:mass`, `:volume` or `:count` when known
    * `scalable` - whether the quantity can be scaled (it is a number)
  """
  @type dimension :: :mass | :volume | :count

  @type t :: %__MODULE__{
          name: String.t(),
          quantity: Decimal.t() | String.t() | nil,
          unit: String.t() | nil,
          note: String.t() | nil,
          optional: boolean(),
          key: String.t(),
          canonical_unit: String.t() | nil,
          dimension: dimension() | nil,
          scalable: boolean()
        }

  defstruct name: "",
            quantity: nil,
            unit: nil,
            note: nil,
            optional: false,
            key: "",
            canonical_unit: nil,
            dimension: nil,
            scalable: false
end
