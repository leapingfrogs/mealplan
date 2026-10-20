defmodule Mealplan.Cooklang.Inline do
  @moduledoc false
  # Parses one line of a step into text and components:
  #
  #   * `@name`, `#name`, `~name` - one word, ending at whitespace or
  #     punctuation (Unicode-aware)
  #   * `@several words{...}` - a name of any length, ended by braces
  #   * `~{...}` - a timer with no name
  #   * `@?` / `#?` - optional ingredient or cookware
  #   * `@name{...}(note)` - an ingredient's preparation note
  #
  # A sigil that doesn't start a valid component is plain text.

  alias Mealplan.Cooklang.Cookware
  alias Mealplan.Cooklang.Ingredient
  alias Mealplan.Cooklang.Normalise
  alias Mealplan.Cooklang.Quantity
  alias Mealplan.Cooklang.Step
  alias Mealplan.Cooklang.Text
  alias Mealplan.Cooklang.Timer
  alias Mealplan.Cooklang.Warning

  @spec parse(String.t(), pos_integer()) :: {[Step.item()], [Warning.t()]}
  def parse(line, line_number), do: scan(line, line_number, [], [])

  defp scan(line, n, items, warnings) do
    case :binary.match(line, ["@", "#", "~"]) do
      :nomatch ->
        {Enum.reverse(add_text(items, line)), Enum.reverse(warnings)}

      {position, 1} ->
        <<before::binary-size(^position), sigil, rest::binary>> = line
        items = add_text(items, before)

        case component(sigil, rest, n) do
          {:ok, item, rest, new_warnings} ->
            scan(rest, n, [item | items], Enum.reverse(new_warnings, warnings))

          :error ->
            scan(rest, n, add_text(items, <<sigil>>), warnings)
        end
    end
  end

  defp component(?~, rest, n) do
    case braced(rest, :optional_name) do
      {:ok, name, content, rest} ->
        {quantity, unit, warnings} = Quantity.parse(content, n)
        {:ok, %Timer{name: blank_to_nil(name), quantity: quantity, unit: unit}, rest, warnings}

      :error ->
        with {:ok, name, rest} <- word(rest) do
          {:ok, %Timer{name: name}, rest, []}
        end
    end
  end

  defp component(sigil, rest, n) do
    {optional, rest} =
      case rest do
        "?" <> rest -> {true, rest}
        rest -> {false, rest}
      end

    case braced(rest, :name) do
      {:ok, name, content, rest} ->
        braced_component(sigil, String.trim(name), content, optional, rest, n)

      :error ->
        with {:ok, name, rest} <- word(rest) do
          {:ok, item(sigil, name, nil, nil, optional), rest, []}
        end
    end
  end

  defp braced_component(?@, name, content, optional, rest, n) do
    {quantity, unit, warnings} = Quantity.parse(content, n)

    {note, rest} = note(rest)
    ingredient = %{item(?@, name, quantity, unit, optional) | note: note}
    {:ok, ingredient, rest, warnings}
  end

  defp braced_component(?#, name, content, optional, rest, n) do
    {quantity, unit, warnings} = Quantity.parse(content, n)

    warnings =
      if unit,
        do: [cookware_unit_warning(name, unit, n) | warnings],
        else: warnings

    {:ok, item(?#, name, quantity, nil, optional), rest, warnings}
  end

  defp cookware_unit_warning(name, unit, n) do
    %Warning{line: n, message: "Cookware has no units, so \"#{unit}\" on #{name} was ignored."}
  end

  defp item(?@, name, quantity, unit, optional) do
    Normalise.ingredient(%Ingredient{
      name: name,
      quantity: quantity,
      unit: unit,
      optional: optional
    })
  end

  defp item(?#, name, quantity, _unit, optional) do
    %Cookware{name: name, quantity: quantity, optional: optional}
  end

  # `name{content}`: the name runs to the first `{` and can't contain a
  # sigil or start with whitespace; the content runs to the next `}`.
  #
  # Regexes run only on short, bounded pieces: matching against the rest of
  # a long line checks the whole remainder each time, which made lines full
  # of sigils quadratic.
  defp braced(rest, name_rule) do
    with {name_end, "{"} <- first_of(rest, ["@", "#", "~", "{", "}"], 0),
         name = binary_part(rest, 0, name_end),
         true <- name_allowed?(name, name_rule),
         {content_end, "}"} <- first_of(rest, ["{", "}"], name_end + 1) do
      content = binary_part(rest, name_end + 1, content_end - name_end - 1)
      {:ok, name, content, from(rest, content_end + 1)}
    else
      _no_match -> :error
    end
  end

  defp name_allowed?("", rule), do: rule == :optional_name
  defp name_allowed?(name, _rule), do: not Regex.match?(~r/\A\s/u, name)

  # `(note)` straight after an ingredient's braces.
  defp note("(" <> inside = rest) do
    case first_of(inside, ["(", ")"], 0) do
      {note_end, ")"} ->
        {blank_to_nil(binary_part(inside, 0, note_end)), from(inside, note_end + 1)}

      _no_note ->
        {nil, rest}
    end
  end

  defp note(rest), do: {nil, rest}

  # One word: up to whitespace or punctuation. The regex sees only the text
  # up to the next ASCII space or sigil, which bounds the work per sigil.
  defp word(rest) do
    prefix =
      case :binary.match(rest, [" ", "@", "#", "~"]) do
        {position, 1} -> binary_part(rest, 0, position)
        :nomatch -> rest
      end

    case Regex.run(~r/\A[^\s\p{P}]+/u, prefix) do
      [word] -> {:ok, word, from(rest, byte_size(word))}
      nil -> :error
    end
  end

  defp first_of(text, patterns, start) do
    case :binary.match(text, patterns, scope: {start, byte_size(text) - start}) do
      {position, length} -> {position, binary_part(text, position, length)}
      :nomatch -> :nomatch
    end
  end

  defp from(text, position), do: binary_part(text, position, byte_size(text) - position)

  defp add_text(items, ""), do: items
  defp add_text([%Text{value: last} | items], text), do: [%Text{value: last <> text} | items]
  defp add_text(items, text), do: [%Text{value: text} | items]

  defp blank_to_nil(text) do
    case String.trim(text) do
      "" -> nil
      text -> text
    end
  end
end
