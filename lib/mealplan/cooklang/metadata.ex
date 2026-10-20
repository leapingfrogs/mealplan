defmodule Mealplan.Cooklang.Metadata do
  @moduledoc false
  # Front matter and `>> key: value` lines. Only the flat subset of YAML is
  # read (ADR 13): `key: value`, inline lists `[a, b]` and `- item` lists.
  # Anything else is reported rather than guessed at.

  alias Mealplan.Cooklang.Warning

  @type entries :: %{String.t() => String.t() | [String.t()]}

  @doc "Reads front matter lines (`{text, line_number}`)."
  @spec front_matter([{String.t(), pos_integer()}]) :: {entries(), [Warning.t()]}
  def front_matter(lines) do
    {entries, _list_key, warnings} =
      Enum.reduce(lines, {%{}, nil, []}, fn {text, line}, {entries, list_key, warnings} ->
        read_line(text, line, entries, list_key, warnings)
      end)

    {entries, Enum.reverse(warnings)}
  end

  defp read_line(text, line, entries, list_key, warnings) do
    cond do
      String.trim(text) == "" or String.starts_with?(text, "#") ->
        {entries, list_key, warnings}

      list_key && Regex.match?(~r/\A\s*-(\s|\z)/u, text) ->
        item = text |> String.trim() |> String.trim_leading("-") |> unquote_value()
        {Map.update(entries, list_key, [item], &append(&1, item)), list_key, warnings}

      true ->
        case entry(text) do
          {:ok, key, ""} -> {Map.put(entries, key, ""), key, warnings}
          {:ok, key, value} -> {Map.put(entries, key, value), nil, warnings}
          :error -> {entries, nil, [unreadable(line) | warnings]}
        end
    end
  end

  defp append(items, item) when is_list(items), do: items ++ [item]
  defp append(_empty, item), do: [item]

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
