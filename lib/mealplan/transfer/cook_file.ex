defmodule Mealplan.Transfer.CookFile do
  @moduledoc """
  Writing Cooklang files for export: front matter that carries a recipe's
  name and servings, and file names that are safe everywhere.
  """

  # Keys the database owns; any other metadata in the source is kept.
  @managed ~w(title servings serves)

  @doc """
  Returns `source` with front matter setting `title` and `servings`, keeping
  the other front matter lines and dropping `>> title/servings/serves` lines
  from the body (they would override the front matter when read back).

      iex> Mealplan.Transfer.CookFile.with_metadata("Mix @flour{100%g}.", "Pancakes", 4)
      "---\\ntitle: Pancakes\\nservings: 4\\n---\\nMix @flour{100%g}.\\n"
  """
  @spec with_metadata(String.t(), String.t(), pos_integer()) :: String.t()
  def with_metadata(source, title, servings) do
    {front, body} = split_front_matter(source)

    lines =
      ["---", "title: #{yaml_value(title)}", "servings: #{servings}"] ++
        drop_managed(front) ++ ["---"] ++ drop_legacy(body)

    lines |> Enum.join("\n") |> String.trim_trailing() |> Kernel.<>("\n")
  end

  defp split_front_matter(source) do
    lines = String.split(source, "\n")

    with ["---" <> _ = first | rest] <- lines,
         true <- String.trim(first) == "---",
         {front, [_closing | body]} <- Enum.split_while(rest, &(String.trim(&1) != "---")) do
      {front, body}
    else
      _no_front_matter -> {[], lines}
    end
  end

  # Drops managed keys, with any indented or list lines that belong to them.
  defp drop_managed(lines) do
    {kept, _skipping} =
      Enum.reduce(lines, {[], false}, fn line, {kept, skipping} ->
        cond do
          continuation?(line) and skipping -> {kept, true}
          managed_key?(line) -> {kept, true}
          true -> {[line | kept], false}
        end
      end)

    Enum.reverse(kept)
  end

  defp drop_legacy(lines) do
    Enum.reject(lines, fn line ->
      case Regex.run(~r/\A\s*>>\s*([^:]+?)\s*:/u, line, capture: :all_but_first) do
        [key] -> String.downcase(key) in @managed
        nil -> false
      end
    end)
  end

  defp continuation?(line), do: Regex.match?(~r/\A(\s|-)/u, line)

  defp managed_key?(line) do
    case Regex.run(~r/\A([^\s:][^:]*?)\s*:/u, line, capture: :all_but_first) do
      [key] -> String.downcase(key) in @managed
      nil -> false
    end
  end

  # Plain unless YAML would read it as something else.
  defp yaml_value(text) do
    if Regex.match?(~r/\A[\[\]{}"'&*!|>%@`#,?:-]|:\s|\s#|\s\z|:\z/u, text),
      do: ~s("#{text |> String.replace("\\", "\\\\") |> String.replace(~s("), ~s(\\"))}"),
      else: text
  end

  @doc """
  A file name for `name` (without extension): characters that are unsafe in
  file names or Cooklang references become `-`, at most 100 characters.

      iex> Mealplan.Transfer.CookFile.file_name("Mac & cheese: 2/3 @home")
      "Mac & cheese- 2-3 -home"
  """
  @spec file_name(String.t()) :: String.t()
  def file_name(name) do
    name
    |> String.replace(~r/[\/\\:*?"<>|@#~{}\x00-\x1f\x7f]/u, "-")
    # "--" and "[-" would start Cooklang comments in menu references.
    |> String.replace(~r/-{2,}/, "-")
    |> String.replace("[", "(")
    |> String.replace("]", ")")
    |> String.trim()
    |> String.trim_leading(".")
    |> String.slice(0, 100)
    |> String.trim()
    |> case do
      "" -> "Untitled"
      file_name -> file_name
    end
  end

  @doc """
  Unique file names for `names`, in order: repeats (ignoring case, as some
  file systems do) get " (2)", " (3)"...
  """
  @spec unique_file_names([String.t()]) :: [String.t()]
  def unique_file_names(names) do
    {file_names, _taken} =
      Enum.map_reduce(names, MapSet.new(), fn name, taken ->
        base = file_name(name)

        unique =
          1
          |> Stream.iterate(&(&1 + 1))
          |> Stream.map(fn
            1 -> base
            n -> "#{base} (#{n})"
          end)
          |> Enum.find(&(not MapSet.member?(taken, String.downcase(&1))))

        {unique, MapSet.put(taken, String.downcase(unique))}
      end)

    file_names
  end
end
