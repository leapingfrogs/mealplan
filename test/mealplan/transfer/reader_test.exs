defmodule Mealplan.Transfer.ReaderTest do
  use Mealplan.DataCase, async: true
  use ExUnitProperties

  import Mealplan.HouseholdsFixtures
  import Mealplan.MealsFixtures
  import Mealplan.RecipesFixtures

  alias Mealplan.Transfer
  alias Mealplan.Transfer.Bundle
  alias Mealplan.Transfer.ImportedMeal
  alias Mealplan.Transfer.ImportedRecipe

  defp zip(entries) do
    files = for {path, content} <- entries, do: {String.to_charlist(path), content}
    {:ok, {_name, binary}} = :zip.create(~c"t.zip", files, [:memory])
    binary
  end

  defp messages(bundle), do: Enum.map(bundle.problems, &{&1.file, &1.message})

  describe "reading an export" do
    test "gives back the recipes and meals" do
      %{scope: scope} = household_fixture()

      chilli =
        recipe_fixture(scope, %{name: "Chilli", servings: 4, source: "Cook @beans{400%g}."})

      rice = recipe_fixture(scope, %{name: "Rice", servings: 2})
      meal_fixture(scope, %{name: "Chilli and rice"}, [chilli, rice])
      meal_fixture(scope, %{name: "Eat out"})
      {:ok, {name, zip}} = Transfer.export(scope)

      bundle = Transfer.read([{name, zip}])

      assert bundle.problems == []

      assert [
               %ImportedRecipe{name: "Chilli", servings: 4, path: "recipes/chilli", warnings: []} =
                 c,
               %ImportedRecipe{name: "Rice", servings: 2, path: "recipes/rice"}
             ] = bundle.recipes

      assert c.source =~ "Cook @beans{400%g}."
      assert c.file == "#{name}/recipes/Chilli.cook"

      assert [
               %ImportedMeal{
                 name: "Chilli and rice",
                 references: [{:path, "recipes/chilli"}, {:path, "recipes/rice"}]
               },
               %ImportedMeal{name: "Eat out", references: []}
             ] = bundle.meals
    end
  end

  describe "loose files" do
    test "recipes take their name from the title, else the file name" do
      bundle =
        Transfer.read([
          {"pancakes.cook",
           "---\ntitle: Best pancakes\nservings: 3 people\n---\nMix @flour{100%g}."},
          {"Beans on toast.COOK", "﻿Toast @bread{2%slices}.\r\nAdd @beans."},
          {"x.cook", "---\ntitle: \"  \"\n---\n[- never closed"}
        ])

      assert [
               %ImportedRecipe{name: "Best pancakes", servings: 3, path: "pancakes"},
               %ImportedRecipe{
                 name: "Beans on toast",
                 servings: nil,
                 source: "Toast @bread{2%slices}.\nAdd @beans."
               },
               %ImportedRecipe{name: "x", warnings: [%{message: "This block comment" <> _}]}
             ] = bundle.recipes
    end

    test "menus: named sections are meals, references by path or name" do
      menu = """
      @./stray{}

      = Sunday roast
      @./Mains/Roast Chicken.cook{2} and @Roast potatoes{} -- comment
      Some other text.

      ===

      == Eat out ==
      """

      bundle = Transfer.read([{"week.menu", menu}])

      assert bundle.meals == [
               %ImportedMeal{
                 file: "week.menu",
                 name: "Sunday roast",
                 references: [{:path, "mains/roast chicken"}, {:name, "Roast potatoes"}]
               },
               %ImportedMeal{file: "week.menu", name: "Eat out", references: []}
             ]

      assert messages(bundle) == [
               {"week.menu", "has recipes outside a named section; they were left out."}
             ]
    end
  end

  describe "problems" do
    test "files that aren't text, or are the wrong kind or too long" do
      bundle =
        Transfer.read([
          {"photo.jpg", "x"},
          {"bad.cook", <<0xFF, 0xFE>>},
          {"long.cook", String.duplicate("a", 50_001)},
          {"huge.menu", String.duplicate("a", 200_001)}
        ])

      assert bundle.recipes == []

      assert messages(bundle) == [
               {"photo.jpg", "isn't a .zip, .cook or .menu file, so it was left out."},
               {"bad.cook", "isn't UTF-8 text, so it was left out."},
               {"long.cook", "is longer than 50000 characters, so it was left out."},
               {"huge.menu", "is longer than 50000 characters, so it was left out."}
             ]
    end

    test "too many files, or too much in total" do
      assert %Bundle{problems: [%{message: "At most 200" <> _}]} =
               Transfer.read(for n <- 1..201, do: {"#{n}.cook", ""})

      assert %Bundle{problems: [%{message: "Uploads can be at most 10 MB" <> _}]} =
               Transfer.read([{"a.zip", :binary.copy(<<0>>, 10 * 1024 * 1024 + 1)}])
    end

    test "zips: other files, hidden files, folders and nested zips" do
      zip =
        zip([
          {"folder/", ""},
          {"folder/Chilli.cook", "@beans"},
          {".DS_Store", "x"},
          {"__MACOSX/folder/._Chilli.cook", "x"},
          {"folder/.hidden/x.cook", "x"},
          {"notes.txt", "x"},
          {"inner.zip", zip([{"a.cook", "x"}])},
          {"../../escape.cook", "@salt"}
        ])

      bundle = Transfer.read([{"stuff.zip", zip}])

      assert Enum.map(bundle.recipes, &{&1.name, &1.path}) == [{"Chilli", "folder/chilli"}]

      assert messages(bundle) == [
               {"stuff.zip/notes.txt", "isn't a .cook or .menu file, so it was left out."},
               {"stuff.zip/inner.zip", "isn't a .cook or .menu file, so it was left out."},
               {"stuff.zip/../../escape.cook", "has a path outside the zip, so it was left out."}
             ]
    end

    test "not a zip, too many entries, or unzipping too big" do
      assert messages(Transfer.read([{"x.zip", "not a zip"}])) == [
               {"x.zip", "isn't a zip file we can read."}
             ]

      many = zip(for n <- 1..501, do: {"#{n}.cook", ""})

      assert [{"many.zip", "has more than 500 files" <> _}] =
               messages(Transfer.read([{"many.zip", many}]))

      big = zip([{"a.cook", :binary.copy(" ", 21 * 1024 * 1024)}])

      assert [{"big.zip", "unzips to more than 20 MB" <> _}] =
               messages(Transfer.read([{"big.zip", big}]))
    end

    test "a zip lying about its sizes is still capped" do
      bomb = zip([{"bomb.cook", :binary.copy(" ", 21 * 1024 * 1024)}])

      # Claim the entry unzips to 100 bytes in the central directory.
      [before, central] = :binary.split(bomb, <<0x02014B50::little-32>>)
      <<header::binary-size(20), _size::little-32, rest::binary>> = central
      lying = before <> <<0x02014B50::little-32>> <> header <> <<100::little-32>> <> rest

      assert [{"bomb.zip/bomb.cook", "unzips to more than 20 MB" <> _}] =
               messages(Transfer.read([{"bomb.zip", lying}]))
    end

    test "encrypted, unusual or broken entries" do
      zip = zip([{"a.cook", String.duplicate("@salt ", 100)}])

      # Set the "encrypted" flag in the local header.
      <<sig::binary-size(6), flags::little-16, rest::binary>> = zip
      encrypted = sig <> <<Bitwise.bor(flags, 1)::little-16>> <> rest

      assert [{"e.zip/a.cook", "is encrypted" <> _}] =
               messages(Transfer.read([{"e.zip", encrypted}]))

      # An unknown compression method.
      <<head::binary-size(8), _method::little-16, rest::binary>> = zip
      odd = head <> <<99::little-16>> <> rest

      assert [{"o.zip/a.cook", "uses a compression" <> _}] =
               messages(Transfer.read([{"o.zip", odd}]))

      # Corrupt compressed data (after the 30-byte header, name and extra field).
      <<_::binary-size(26), name_length::little-16, extra_length::little-16, _::binary>> = zip
      start = 30 + name_length + extra_length + 2
      <<head::binary-size(^start), _data::binary-size(4), rest::binary>> = zip
      corrupt = head <> <<0xFF, 0xFF, 0xFF, 0xFF>> <> rest
      assert [{"c.zip/a.cook", _message}] = messages(Transfer.read([{"c.zip", corrupt}]))
    end

    test "zips from other tools: a top-level folder, streamed entries with data descriptors" do
      # Made with Info-ZIP writing to a pipe (`zip -r - "My recipes" | cat`).
      zip = File.read!("test/support/fixtures/transfer/streamed.zip")

      bundle = Transfer.read([{"My recipes.zip", zip}])

      assert bundle.problems == []

      assert [
               %ImportedRecipe{
                 name: "Crème brûlée",
                 servings: 6,
                 path: "my recipes/recipes/creme brulee"
               }
             ] =
               bundle.recipes

      assert [%ImportedMeal{name: "Pudding night", references: [{:path, "recipes/creme brulee"}]}] =
               bundle.meals
    end

    test "stored (uncompressed) entries are read too" do
      {:ok, {_name, stored}} =
        :zip.create(~c"s.zip", [{~c"a.cook", "@salt"}], [:memory, {:uncompress, :all}])

      assert [%ImportedRecipe{name: "a"}] = Transfer.read([{"s.zip", stored}]).recipes
    end

    test "a recipe file with a blank name is Untitled" do
      assert [%ImportedRecipe{name: "Untitled"}] = Transfer.read([{"  .cook", "@salt"}]).recipes
    end
  end

  describe "never raises" do
    property "on any bytes, as any kind of file" do
      check all bytes <- binary(max_length: 2000),
                extension <- member_of([".zip", ".cook", ".menu", ".txt"]),
                max_runs: 300 do
        assert %Bundle{} = Transfer.read([{"f" <> extension, bytes}])
      end
    end

    property "on zips of anything" do
      check all entries <-
                  list_of(
                    tuple(
                      {member_of(["a.cook", "b.menu", "c/d.cook", ".e.cook", "f.txt", "g/"]),
                       binary(max_length: 300)}
                    ),
                    max_length: 8
                  ),
                max_runs: 200 do
        entries = Enum.uniq_by(entries, &elem(&1, 0))
        assert %Bundle{} = Transfer.read([{"z.zip", zip(entries)}])
      end
    end

    property "on damaged zips" do
      zip = zip([{"a.cook", String.duplicate("@salt{1%g} ", 200)}, {"b.menu", "= M\n@./a{}"}])

      check all position <- integer(0..(byte_size(zip) - 1)),
                byte <- integer(0..255),
                max_runs: 300 do
        <<head::binary-size(^position), _old, rest::binary>> = zip
        assert %Bundle{} = Transfer.read([{"z.zip", head <> <<byte>> <> rest}])
      end
    end
  end

  test "limits/0" do
    assert %{upload_bytes: 10_485_760, files: 200, zip_entries: 500} = Transfer.limits()
  end
end
