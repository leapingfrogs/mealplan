defmodule Mealplan.Transfer.Reader do
  @moduledoc """
  Reads uploaded files into a `Mealplan.Transfer.Bundle` (iteration 2
  design, "Reading an import"). Pure and in memory: entry names are only
  ever keys, nothing is written to disk, and any input gives a bundle,
  never an exception.

  Zips are inflated entry by entry with a running cap, so a zip that lies
  about its sizes still can't use more than the limit.
  """
  alias Mealplan.Cooklang
  alias Mealplan.Transfer.Bundle
  alias Mealplan.Transfer.ImportedMeal
  alias Mealplan.Transfer.ImportedRecipe

  @max_upload 10 * 1024 * 1024
  @max_files 200
  @max_entries 500
  @max_unzipped 20 * 1024 * 1024
  @max_source 50_000
  @max_name 120

  @doc "The limits, for the upload form and messages."
  def limits do
    %{
      upload_bytes: @max_upload,
      files: @max_files,
      zip_entries: @max_entries,
      unzipped_bytes: @max_unzipped,
      recipe_characters: @max_source
    }
  end

  @doc "Reads `{file_name, binary}` uploads into a bundle."
  @spec read([{String.t(), binary()}]) :: Bundle.t()
  def read(uploads) when is_list(uploads) do
    total = uploads |> Enum.map(fn {_name, binary} -> byte_size(binary) end) |> Enum.sum()

    cond do
      length(uploads) > @max_files ->
        problem_bundle("upload", "At most #{@max_files} files can be imported at once.")

      total > @max_upload ->
        problem_bundle("upload", "Uploads can be at most #{megabytes(@max_upload)} in total.")

      true ->
        uploads
        |> Enum.flat_map(&expand/1)
        |> Enum.reduce(%Bundle{}, &add/2)
        |> finish()
    end
  end

  defp problem_bundle(file, message), do: %Bundle{problems: [%{file: file, message: message}]}

  # A zip becomes its entries; other files stay as they are. Each item is
  # {:file, display_name, path_in_upload, binary} or {:problem, file, message}.
  defp expand({name, binary}) do
    if extension(name) == ".zip",
      do: unzip(name, binary),
      else: [{:file, name, name, binary}]
  end

  ## Zips

  defp unzip(zip_name, binary) do
    case list_zip(binary) do
      {:ok, entries} when length(entries) > @max_entries ->
        [{:problem, zip_name, "has more than #{@max_entries} files, so it wasn't read."}]

      {:ok, entries} ->
        declared = entries |> Enum.map(& &1.size) |> Enum.sum()

        if declared > @max_unzipped,
          do: [{:problem, zip_name, too_big_unzipped()}],
          else: read_entries(zip_name, binary, entries)

      :error ->
        [{:problem, zip_name, "isn't a zip file we can read."}]
    end
  end

  defp list_zip(binary) do
    case :zip.list_dir(binary) do
      {:ok, listing} ->
        entries =
          for {:zip_file, name, info, _comment, offset, compressed} <- listing do
            %{
              name: List.to_string(name),
              size: elem(info, 1),
              offset: offset,
              compressed: compressed
            }
          end

        {:ok, entries}

      _error ->
        :error
    end
  catch
    _kind, _reason -> :error
  end

  defp read_entries(zip_name, binary, entries) do
    {items, _used} =
      Enum.flat_map_reduce(entries, 0, fn entry, used ->
        read_entry(binary, entry, "#{zip_name}/#{entry.name}", used)
      end)

    items
  end

  # Returns {items, bytes used so far}.
  defp read_entry(binary, entry, path, used) do
    cond do
      String.ends_with?(entry.name, "/") ->
        {[], used}

      outside?(entry.name) ->
        {[{:problem, path, "has a path outside the zip, so it was left out."}], used}

      hidden?(entry.name) ->
        {[], used}

      extension(entry.name) not in [".cook", ".menu"] ->
        {[{:problem, path, "isn't a .cook or .menu file, so it was left out."}], used}

      true ->
        unzip_entry(binary, entry, path, used)
    end
  end

  defp unzip_entry(binary, entry, path, used) do
    case inflate(binary, entry, @max_unzipped - used) do
      {:ok, content} -> {[{:file, path, entry.name, content}], used + byte_size(content)}
      {:error, message} -> {[{:problem, path, message}], used}
    end
  end

  defp outside?(path) do
    String.starts_with?(path, "/") or ".." in String.split(path, ["/", "\\"])
  end

  # Hidden files and folders (.DS_Store, __MACOSX/) are skipped quietly.
  defp hidden?(path) do
    path
    |> String.split("/")
    |> Enum.any?(&(String.starts_with?(&1, ".") or &1 == "__MACOSX"))
  end

  # Inflates one entry from its local header, stopping at `allowance` bytes.
  defp inflate(binary, %{offset: offset, compressed: compressed}, allowance) do
    with <<_before::binary-size(^offset), 0x04034B50::little-32, _version::16, flags::little-16,
           method::little-16, _time::16, _date::16, crc::little-32, _sizes::64,
           name_length::little-16, extra_length::little-16, rest::binary>> <- binary,
         <<_name_and_extra::binary-size(^name_length + ^extra_length),
           data::binary-size(^compressed), after_data::binary>> <- rest,
         {:ok, content} <- decompress(flags, method, data, allowance) do
      checked(content, expected_crc(flags, crc, after_data))
    else
      {:error, _message} = error -> error
      _malformed -> {:error, "couldn't be read from the zip."}
    end
  end

  defp decompress(flags, method, data, allowance) do
    cond do
      Bitwise.band(flags, 1) == 1 -> {:error, "is encrypted, so it wasn't read."}
      method == 0 -> capped(data, allowance)
      method == 8 -> inflate_capped(data, allowance)
      true -> {:error, "uses a compression we can't read."}
    end
  end

  # With general purpose flag 3 the CRC follows the data, in a descriptor
  # that may or may not start with its own signature.
  defp expected_crc(flags, crc, after_data) do
    if Bitwise.band(flags, 8) == 8 do
      case after_data do
        <<0x08074B50::little-32, crc::little-32, _rest::binary>> -> crc
        <<crc::little-32, _rest::binary>> -> crc
        _missing -> nil
      end
    else
      crc
    end
  end

  defp checked(content, crc) do
    if :erlang.crc32(content) == crc,
      do: {:ok, content},
      else: {:error, "is damaged (its checksum doesn't match), so it wasn't read."}
  end

  defp capped(data, allowance) when byte_size(data) <= allowance, do: {:ok, data}
  defp capped(_data, _allowance), do: {:error, too_big_unzipped()}

  defp inflate_capped(data, allowance) do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z, -15)
      inflate_loop(z, :zlib.safeInflate(z, data), [], 0, allowance)
    catch
      _kind, _reason -> {:error, "couldn't be read from the zip."}
    after
      :zlib.close(z)
    end
  end

  defp inflate_loop(z, {state, chunk}, acc, size, allowance) do
    size = size + IO.iodata_length(chunk)

    cond do
      size > allowance ->
        {:error, too_big_unzipped()}

      state == :continue ->
        inflate_loop(z, :zlib.safeInflate(z, []), [acc, chunk], size, allowance)

      state == :finished ->
        {:ok, IO.iodata_to_binary([acc, chunk])}
    end
  end

  defp too_big_unzipped, do: "unzips to more than #{megabytes(@max_unzipped)}, so it wasn't read."

  ## Files

  defp add({:problem, file, message}, bundle),
    do: %{bundle | problems: [%{file: file, message: message} | bundle.problems]}

  defp add({:file, display, path, binary}, bundle) do
    case {extension(path), text(binary)} do
      {_extension, :invalid} ->
        add({:problem, display, "isn't UTF-8 text, so it was left out."}, bundle)

      {_extension, {:ok, text}} when byte_size(text) > @max_source * 4 ->
        add({:problem, display, too_long()}, bundle)

      {".cook", {:ok, text}} ->
        add_recipe(bundle, display, path, text)

      {".menu", {:ok, text}} ->
        add_menu(bundle, display, text)

      {_other, _text} ->
        add({:problem, display, "isn't a .zip, .cook or .menu file, so it was left out."}, bundle)
    end
  end

  defp text(binary) do
    binary = String.replace_prefix(binary, <<0xEF, 0xBB, 0xBF>>, "")

    if String.valid?(binary),
      do: {:ok, String.replace(binary, ["\r\n", "\r"], "\n")},
      else: :invalid
  end

  defp add_recipe(bundle, display, path, text) do
    if String.length(text) > @max_source do
      add({:problem, display, too_long()}, bundle)
    else
      parsed = Cooklang.parse(text)

      recipe = %ImportedRecipe{
        file: display,
        path: reference_key(path),
        name: recipe_name(parsed.metadata, path),
        servings: parsed.servings,
        source: text,
        warnings: parsed.warnings
      }

      %{bundle | recipes: [recipe | bundle.recipes]}
    end
  end

  defp too_long, do: "is longer than #{@max_source} characters, so it was left out."

  defp recipe_name(%{"title" => title}, path) when is_binary(title) do
    case clean_name(title) do
      "" -> file_base(path)
      name -> name
    end
  end

  defp recipe_name(_metadata, path), do: file_base(path)

  defp file_base(path) do
    path
    |> String.split("/")
    |> List.last()
    |> String.replace(~r/\.(cook|menu)\z/i, "")
    |> clean_name()
    |> case do
      "" -> "Untitled"
      name -> name
    end
  end

  defp clean_name(name),
    do: name |> String.split() |> Enum.join(" ") |> String.slice(0, @max_name)

  # Each named section is a meal; its ingredients are the recipe references.
  defp add_menu(bundle, display, text) do
    parsed = Cooklang.parse(text)

    {meals, problems} =
      Enum.reduce(parsed.sections, {[], []}, fn section, {meals, problems} ->
        references =
          for %{items: items} <- section.blocks,
              %Cooklang.Ingredient{name: name} <- items,
              do: reference(name)

        case {section.name && clean_name(section.name), references} do
          {name, _references} when name not in [nil, ""] ->
            {[%ImportedMeal{file: display, name: name, references: references} | meals], problems}

          {_no_name, []} ->
            {meals, problems}

          {_no_name, _references} ->
            {meals,
             [
               %{
                 file: display,
                 message: "has recipes outside a named section; they were left out."
               }
               | problems
             ]}
        end
      end)

    %{bundle | meals: meals ++ bundle.meals, problems: problems ++ bundle.problems}
  end

  defp reference("./" <> path), do: {:path, reference_key(path)}
  defp reference(name), do: {:name, clean_name(name)}

  # Lower-case path without a leading "./" or the .cook extension.
  defp reference_key(path) do
    path
    |> String.trim_leading("./")
    |> String.replace(~r/\.cook\z/i, "")
    |> String.downcase()
  end

  defp extension(name), do: name |> Path.extname() |> String.downcase()

  defp finish(bundle) do
    %{
      bundle
      | recipes: Enum.reverse(bundle.recipes),
        meals: Enum.reverse(bundle.meals),
        problems: Enum.reverse(bundle.problems)
    }
  end

  defp megabytes(bytes), do: "#{div(bytes, 1024 * 1024)} MB"
end
