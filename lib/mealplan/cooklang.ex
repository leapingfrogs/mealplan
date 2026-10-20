defmodule Mealplan.Cooklang do
  @moduledoc """
  Parses [Cooklang](https://cooklang.org) recipe text: the base
  specification (version 8) as checked by its canonical tests (ADR 13).

  `parse/1` is a pure function that accepts any text and never raises;
  anything it can't make sense of is kept as text or reported in
  `warnings`.

  Supported:

    * steps (paragraphs; a line ending in `\\` forces a line break)
    * ingredients `@salt`, `@ground pepper{}`, `@flour{250%g}(sifted)`
    * cookware `#pan`, `#frying pan{}`, timers `~{10%minutes}`, `~eggs{3%min}`
    * optional `@?` and `#?`
    * `--` line comments and `[- block comments -]`
    * front matter between `---` lines, and `>> key: value` lines
    * sections (`= Dough`, `== Filling ==`) and notes (`> ...`)
  """

  alias Mealplan.Cooklang.Inline
  alias Mealplan.Cooklang.Metadata
  alias Mealplan.Cooklang.Note
  alias Mealplan.Cooklang.Recipe
  alias Mealplan.Cooklang.Section
  alias Mealplan.Cooklang.Step
  alias Mealplan.Cooklang.Text
  alias Mealplan.Cooklang.Warning

  @doc """
  Parses Cooklang text into a `Mealplan.Cooklang.Recipe`.

      iex> recipe = Mealplan.Cooklang.parse("Add @salt{1%tsp}.")
      iex> [salt] = recipe.ingredients
      iex> {salt.name, Decimal.to_string(salt.quantity), salt.unit}
      {"salt", "1", "tsp"}
  """
  @spec parse(String.t() | nil) :: Recipe.t()
  def parse(nil), do: parse("")

  def parse(source) when is_binary(source) do
    {source, encoding_warnings} = sanitise(source)

    lines =
      source
      |> String.replace(["\r\n", "\r"], "\n")
      |> String.split("\n")
      |> Enum.with_index(1)

    {front_matter, body, front_warnings} = split_front_matter(lines)
    {metadata, metadata_warnings} = Metadata.front_matter(front_matter)
    {body, comment_warnings} = strip_comments(body)
    {sections, legacy_metadata, body_warnings} = blocks(body)

    metadata = Map.merge(metadata, legacy_metadata)
    items = for %Section{blocks: blocks} <- sections, %Step{items: items} <- blocks, do: items
    items = List.flatten(items)

    %Recipe{
      metadata: metadata,
      servings: servings(metadata),
      sections: sections,
      ingredients: Enum.filter(items, &is_struct(&1, Mealplan.Cooklang.Ingredient)),
      cookware: Enum.filter(items, &is_struct(&1, Mealplan.Cooklang.Cookware)),
      timers: Enum.filter(items, &is_struct(&1, Mealplan.Cooklang.Timer)),
      warnings:
        Enum.concat([
          encoding_warnings,
          front_warnings,
          metadata_warnings,
          comment_warnings,
          body_warnings
        ])
    }
  end

  defp sanitise(source) do
    source = String.replace_prefix(source, <<0xEF, 0xBB, 0xBF>>, "")

    if String.valid?(source) do
      {source, []}
    else
      {String.replace_invalid(source),
       [%Warning{message: "The text had invalid characters, which were replaced."}]}
    end
  end

  ## Front matter

  defp split_front_matter([{first, 1} | rest] = lines) do
    if front_matter_fence?(first),
      do: close_front_matter(lines, rest),
      else: {[], lines, []}
  end

  defp close_front_matter(lines, rest) do
    case Enum.split_while(rest, fn {text, _n} -> not front_matter_fence?(text) end) do
      {front_matter, [_closing | body]} ->
        {front_matter, body, []}

      {_unclosed, []} ->
        {[], lines, [%Warning{line: 1, message: "The metadata block is never closed with ---."}]}
    end
  end

  defp front_matter_fence?(text), do: String.trim_trailing(text) == "---"

  ## Comments

  # Removes `--` and `[- -]` comments. Lines left blank by a comment are
  # dropped rather than treated as blank lines, so they don't split steps.
  defp strip_comments(lines) do
    {lines, open} =
      Enum.flat_map_reduce(lines, nil, fn {text, n}, open ->
        {kept, touched?, open} = uncomment(text, n, open, [], false)
        kept = IO.iodata_to_binary(kept)

        cond do
          String.trim(kept) != "" -> {[{:line, kept, n}], open}
          touched? -> {[], open}
          true -> {[:blank], open}
        end
      end)

    warnings =
      if open,
        do: [%Warning{line: open, message: "This block comment is never closed with -]."}],
        else: []

    {lines, warnings}
  end

  defp uncomment(text, n, nil, kept, touched?) do
    case comment_start(text, 0) do
      nil ->
        {[kept, text], touched?, nil}

      {position, marker} ->
        <<before::binary-size(^position), _marker::binary-size(2), rest::binary>> = text

        case marker do
          "--" -> {[kept, before], true, nil}
          "[-" -> uncomment(rest, n, n, [kept, before], true)
        end
    end
  end

  defp uncomment(text, n, open, kept, _touched?) do
    case :binary.split(text, "-]") do
      [_comment, rest] -> uncomment(rest, n, nil, kept, true)
      [_comment] -> {kept, true, open}
    end
  end

  # The first `--` or `[-` from `from`. A run of three or more dashes
  # (`---`) is text, not a comment.
  defp comment_start(text, from) do
    case :binary.match(text, ["--", "[-"], scope: {from, byte_size(text) - from}) do
      :nomatch ->
        nil

      {position, 2} ->
        marker = binary_part(text, position, 2)

        if marker == "--" and dash_run(text, position) >= 3 do
          comment_start(text, position + dash_run(text, position))
        else
          {position, marker}
        end
    end
  end

  defp dash_run(text, position) do
    <<_before::binary-size(^position), rest::binary>> = text
    byte_size(rest) - byte_size(String.trim_leading(rest, "-"))
  end

  ## Blocks

  defp blocks(lines) do
    state = %{sections: [], section: %Section{}, step: [], note: [], metadata: %{}, warnings: []}

    state =
      lines
      |> Enum.reduce(state, &block_line/2)
      |> flush()

    sections =
      [state.section | state.sections]
      |> Enum.map(&%{&1 | blocks: Enum.reverse(&1.blocks)})
      |> Enum.reverse()
      |> drop_empty_first_section()

    {sections, state.metadata, Enum.reverse(state.warnings)}
  end

  defp block_line(:blank, state), do: flush(state)

  defp block_line({:line, text, n}, state) do
    trimmed = String.trim_leading(text)

    cond do
      String.starts_with?(trimmed, ">>") ->
        state |> flush() |> legacy_metadata(String.slice(trimmed, 2..-1//1), n)

      String.starts_with?(trimmed, ">") ->
        note = trimmed |> String.slice(1..-1//1) |> String.trim()
        state |> flush_step() |> Map.update!(:note, &[note | &1])

      String.starts_with?(trimmed, "=") ->
        state = flush(state)
        name = trimmed |> String.trim_leading("=") |> String.trim_trailing() |> String.trim("=")

        %{
          state
          | sections: [state.section | state.sections],
            section: %Section{name: blank_to_nil(String.trim(name))}
        }

      true ->
        state |> flush_note() |> Map.update!(:step, &[{text, n} | &1])
    end
  end

  defp legacy_metadata(state, text, n) do
    case Metadata.entry(String.trim(text)) do
      {:ok, key, value} -> %{state | metadata: Map.put(state.metadata, key, value)}
      :error -> %{state | warnings: [Metadata.unreadable(n) | state.warnings]}
    end
  end

  defp flush(state), do: state |> flush_step() |> flush_note()

  defp flush_note(%{note: []} = state), do: state

  defp flush_note(state) do
    text = state.note |> Enum.reverse() |> Enum.join(" ") |> String.trim()
    add_block(%{state | note: []}, %Note{text: text})
  end

  defp flush_step(%{step: []} = state), do: state

  defp flush_step(state) do
    {items, warnings} = step_items(Enum.reverse(state.step))
    state = %{state | step: [], warnings: Enum.reverse(warnings, state.warnings)}

    case items do
      [] -> state
      items -> add_block(state, %Step{items: items})
    end
  end

  defp add_block(state, block) do
    %{state | section: %{state.section | blocks: [block | state.section.blocks]}}
  end

  # Lines of a paragraph join with a space, or a line break after a
  # trailing backslash. Each line is parsed on its own so names can't run
  # across lines.
  defp step_items(lines) do
    {items, warnings, _separator} =
      Enum.reduce(lines, {[], [], nil}, fn {text, n}, {items, warnings, separator} ->
        {text, next_separator} =
          if String.ends_with?(String.trim_trailing(text), "\\"),
            do: {text |> String.trim_trailing() |> String.trim_trailing("\\"), "\n"},
            else: {text, " "}

        {line_items, line_warnings} = Inline.parse(text, n)
        items = if separator, do: [%Text{value: separator} | items], else: items
        {Enum.reverse(line_items, items), Enum.reverse(line_warnings, warnings), next_separator}
      end)

    {items |> Enum.reverse() |> merge_text() |> trim_ends(), Enum.reverse(warnings)}
  end

  defp merge_text(items) do
    items
    |> Enum.chunk_by(&is_struct(&1, Text))
    |> Enum.flat_map(fn
      [%Text{} | _] = texts -> [%Text{value: Enum.map_join(texts, & &1.value)}]
      components -> components
    end)
  end

  defp trim_ends(items) do
    items
    |> update_first(&String.trim_leading/1)
    |> Enum.reverse()
    |> update_first(&String.trim_trailing/1)
    |> Enum.reverse()
  end

  defp update_first([%Text{value: value} | rest], trim) do
    case trim.(value) do
      "" -> rest
      value -> [%Text{value: value} | rest]
    end
  end

  defp update_first(items, _trim), do: items

  defp drop_empty_first_section([%Section{name: nil, blocks: []} | [_ | _] = rest]), do: rest
  defp drop_empty_first_section(sections), do: sections

  ## Servings

  defp servings(metadata) do
    value = Map.get(metadata, "servings") || Map.get(metadata, "serves")
    value = if is_list(value), do: List.first(value), else: value

    with value when is_binary(value) <- value,
         # The first number: "4", "4 people", "Serves 4", "4 to 6".
         [digits] <- Regex.run(~r/(\d+)/, value, capture: :all_but_first),
         {servings, ""} when servings > 0 <- Integer.parse(digits) do
      servings
    else
      _ -> nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(text), do: text
end
