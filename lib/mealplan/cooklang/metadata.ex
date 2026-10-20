defmodule Mealplan.Cooklang.Metadata do
  @moduledoc false
  # Front matter and `>> key: value` lines. A flat subset of YAML is read
  # (ADR 13): `key: value` (a plain value may wrap onto indented lines),
  # block values (`key: |` keeps line breaks, `key: >` folds them), inline
  # lists `[a, b]` and `- item` lists. Anything else, such as nested maps,
  # is reported rather than guessed at.

  alias Mealplan.Cooklang.Warning

  @type entries :: %{String.t() => String.t() | [String.t()]}

  @doc "Reads front matter lines (`{text, line_number}`)."
  @spec front_matter([{String.t(), pos_integer()}]) :: {entries(), [Warning.t()]}
  def front_matter(lines) do
    state = %{entries: %{}, warnings: [], open: nil}

    %{entries: entries, warnings: warnings} =
      lines
      |> Enum.reduce(state, fn {text, line}, state -> read_line(state, text, line) end)
      |> close()

    {entries, Enum.reverse(warnings)}
  end

  # `open` is what indented lines continue: {:plain, key}, {:list, key} or
  # {:block, key, :literal | :folded, lines}.
  defp read_line(state, text, line) do
    indented? = Regex.match?(~r/\A\s/u, text)

    cond do
      String.trim(text) == "" -> blank(state)
      indented? and state.open != nil -> continue(state, String.trim(text), line)
      String.starts_with?(text, "#") -> state
      list_item?(text) and match?({:list, _key}, state.open) -> add_item(state, text)
      true -> state |> close() |> start_entry(text, line)
    end
  end

  # Blank lines separate paragraphs in a block value; elsewhere they're ignored.
  defp blank(%{open: {:block, key, style, lines}} = state),
    do: %{state | open: {:block, key, style, ["" | lines]}}

  defp blank(state), do: state

  defp continue(%{open: {:block, key, style, lines}} = state, text, _line),
    do: %{state | open: {:block, key, style, [text | lines]}}

  defp continue(%{open: {:plain, key}} = state, text, _line) do
    put_in(state, [:entries, key], "#{state.entries[key]} #{text}")
  end

  defp continue(%{open: {:list, key}} = state, text, line) do
    cond do
      list_item?(text) ->
        add_item(state, text)

      # An indented line after an item continues it.
      is_list(state.entries[key]) ->
        {last, items} = List.pop_at(state.entries[key], -1)
        put_in(state, [:entries, key], items ++ ["#{last} #{text}"])

      true ->
        %{state | warnings: [unreadable(line) | state.warnings]}
    end
  end

  defp list_item?(text), do: Regex.match?(~r/\A\s*-(\s|\z)/u, text)

  defp add_item(%{open: {:list, key}} = state, text) do
    item = text |> String.trim() |> String.trim_leading("-") |> unquote_value()

    items =
      case state.entries[key] do
        items when is_list(items) -> items ++ [item]
        _empty -> [item]
      end

    put_in(state, [:entries, key], items)
  end

  defp start_entry(state, text, line) do
    case entry(text) do
      {:ok, key, ""} ->
        %{state | entries: Map.put(state.entries, key, ""), open: {:list, key}}

      {:ok, key, indicator} when indicator in ["|", "|-", "|+", ">", ">-", ">+"] ->
        style = if String.starts_with?(indicator, "|"), do: :literal, else: :folded
        %{state | entries: Map.put(state.entries, key, ""), open: {:block, key, style, []}}

      {:ok, key, value} when is_binary(value) ->
        %{state | entries: Map.put(state.entries, key, value), open: {:plain, key}}

      {:ok, key, list} ->
        %{state | entries: Map.put(state.entries, key, list), open: nil}

      :error ->
        %{state | warnings: [unreadable(line) | state.warnings], open: nil}
    end
  end

  defp close(%{open: {:block, key, style, lines}} = state) do
    # Lines were collected newest first; trailing blank lines are dropped.
    lines = lines |> Enum.drop_while(&(&1 == "")) |> Enum.reverse()
    value = if style == :literal, do: Enum.join(lines, "\n"), else: fold(lines)
    %{state | entries: Map.put(state.entries, key, value), open: nil}
  end

  defp close(state), do: %{state | open: nil}

  # Folded: lines join with spaces; a blank line becomes a line break.
  defp fold(lines) do
    lines
    |> Enum.chunk_by(&(&1 == ""))
    |> Enum.reject(&(hd(&1) == ""))
    |> Enum.map_join("\n", &Enum.join(&1, " "))
  end

  @doc "Reads one `key: value` entry (also used for `>>` lines)."
  @spec entry(String.t()) :: {:ok, String.t(), String.t() | [String.t()]} | :error
  def entry(text) do
    case Regex.run(~r/\A([^\s:][^:]*?)\s*:\s*(.*?)\s*\z/u, text, capture: :all_but_first) do
      [key, value] -> {:ok, key, value(value)}
      nil -> :error
    end
  end

  @doc "A warning for a metadata line that couldn't be read."
  @spec unreadable(pos_integer()) :: Warning.t()
  def unreadable(line) do
    %Warning{
      line: line,
      message: "Couldn't read this metadata line; use \"key: value\"."
    }
  end

  defp value("[" <> rest = value) do
    if String.ends_with?(rest, "]") do
      rest
      |> String.trim_trailing("]")
      |> String.split(",", trim: true)
      |> Enum.map(&unquote_value/1)
      |> Enum.reject(&(&1 == ""))
    else
      value
    end
  end

  defp value(value), do: unquote_value(value)

  defp unquote_value(value) do
    value = String.trim(value)

    case Regex.run(~r/\A(["'])(.*)\1\z/su, value, capture: :all_but_first) do
      # Double quotes allow YAML's \" and \\ escapes.
      ["\"", inner] -> inner |> String.replace("\\\"", "\"") |> String.replace("\\\\", "\\")
      [_single, inner] -> inner
      nil -> value
    end
  end
end
