defmodule Mealplan.Cooklang.Quantity do
  @moduledoc false
  # The `{quantity%unit}` part of an ingredient, cookware or timer.

  alias Mealplan.Cooklang.Warning

  @type value :: Decimal.t() | String.t() | nil

  @doc """
  Splits braces content into `{quantity, unit, warnings}`. Whole numbers,
  decimals and fractions (`1/2`, `1 / 2`) become `Decimal`s; other text is
  kept as written; empty parts are `nil`.
  """
  @spec parse(String.t(), pos_integer()) :: {value(), String.t() | nil, [Warning.t()]}
  def parse(content, line) do
    {quantity, unit} =
      case String.split(content, "%", parts: 2) do
        [quantity] -> {quantity, nil}
        [quantity, unit] -> {quantity, blank_to_nil(unit)}
      end

    {value, warnings} = value(String.trim(quantity), line)
    {value, unit, warnings}
  end

  defp value("", _line), do: {nil, []}

  defp value(text, line) do
    cond do
      Regex.match?(~r/\A\d+(\.\d+)?\z/, text) ->
        {Decimal.new(text), []}

      # A leading zero ("01/2") is not a fraction, per the spec tests.
      match = Regex.run(~r/\A(0|[1-9]\d*)\s*\/\s*(\d+)\z/, text, capture: :all_but_first) ->
        fraction(match, text, line)

      true ->
        {text, []}
    end
  end

  defp fraction([numerator, denominator], text, line) do
    denominator = Decimal.new(denominator)

    if Decimal.eq?(denominator, 0) do
      {text, [%Warning{line: line, message: "#{text} divides by zero, so it was kept as text."}]}
    else
      {Decimal.div(Decimal.new(numerator), denominator), []}
    end
  end

  defp blank_to_nil(text) do
    case String.trim(text) do
      "" -> nil
      text -> text
    end
  end
end
