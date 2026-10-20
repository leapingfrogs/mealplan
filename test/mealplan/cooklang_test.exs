defmodule Mealplan.CooklangTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Mealplan.Cooklang
  alias Mealplan.Cooklang.Cookware
  alias Mealplan.Cooklang.Ingredient
  alias Mealplan.Cooklang.Note
  alias Mealplan.Cooklang.Recipe
  alias Mealplan.Cooklang.Section
  alias Mealplan.Cooklang.Step
  alias Mealplan.Cooklang.Text
  alias Mealplan.Cooklang.Timer
  alias Mealplan.Cooklang.Warning

  doctest Cooklang
  doctest Mealplan.Cooklang.Normalise

  defp messages(recipe), do: Enum.map(recipe.warnings, &{&1.line, &1.message})

  defp only_step(source) do
    assert [%Section{blocks: [%Step{items: items}]}] = Cooklang.parse(source).sections
    items
  end

  describe "structure" do
    test "empty or missing text gives an empty recipe" do
      assert Cooklang.parse("") == %Recipe{sections: [%Section{}]}
      assert Cooklang.parse(nil) == Cooklang.parse("")
    end

    test "paragraphs are steps; their lines join, a trailing backslash breaks the line" do
      source = "Boil the water,\nthen salt it.\r\n\r\nLine one\\\nline two"

      assert [%Section{blocks: [first, second]}] = Cooklang.parse(source).sections
      assert first == %Step{items: [%Text{value: "Boil the water, then salt it."}]}
      assert second == %Step{items: [%Text{value: "Line one\nline two"}]}
    end

    test "names don't run across lines" do
      assert [%Ingredient{name: "salt"}, %Text{value: " and pepper{} here"}] =
               only_step("@salt and\npepper{} here")
    end

    test "sections and notes" do
      source = """
      > Family favourite.
      > Serve hot.

      Prep.

      = Dough
      Mix.
      == Filling ==
      Fill.
      ===
      Bake.
      """

      assert [
               %Section{name: nil, blocks: [%Note{text: "Family favourite. Serve hot."}, prep]},
               %Section{name: "Dough", blocks: [%Step{items: [%Text{value: "Mix."}]}]},
               %Section{name: "Filling", blocks: [_fill]},
               %Section{name: nil, blocks: [_bake]}
             ] = Cooklang.parse(source).sections

      assert prep == %Step{items: [%Text{value: "Prep."}]}
    end

    test "a note line ends the step before it, and a step line ends the note" do
      assert [%Section{blocks: [%Step{}, %Note{text: "aside"}, %Step{}]}] =
               Cooklang.parse("Step one\n> aside\nStep two").sections
    end

    test "a recipe starting with a section has no empty first section" do
      assert [%Section{name: "Only"}] = Cooklang.parse("= Only\nStep.").sections
    end
  end

  describe "comments" do
    test "block comments are removed, also across lines" do
      source = "Add @milk{4%cup} [- metric? -], keep mixing\nStir [- one\n\ntwo -] well"

      assert [
               %Text{value: "Add "},
               %Ingredient{name: "milk"},
               %Text{value: " , keep mixing Stir   well"}
             ] = only_step(source)
    end

    test "an unclosed block comment hides the rest and warns" do
      recipe = Cooklang.parse("Step\n[- never closed\n\nMore")

      assert [%Section{blocks: [%Step{items: [%Text{value: "Step"}]}]}] = recipe.sections
      assert messages(recipe) == [{2, "This block comment is never closed with -]."}]
    end

    test "dashes inside words and long dash runs are text" do
      assert [%Text{value: "pre---heat"}] = only_step("pre---heat -- comment")
    end
  end

  describe "components" do
    test "ingredients with units, notes and normalisation" do
      assert [
               %Text{value: "Add "},
               %Ingredient{
                 name: "Cherry Tomatoes",
                 quantity: quantity,
                 unit: "Grams",
                 note: "halved",
                 key: "cherry tomato",
                 canonical_unit: "g",
                 dimension: :mass,
                 scalable: true
               },
               %Text{value: "."}
             ] = only_step("Add @Cherry Tomatoes{250%Grams}(halved).")

      assert Decimal.eq?(quantity, 250)
    end

    test "fractions and decimals are numbers; other quantities are text" do
      recipe = Cooklang.parse("@a{1/3} @b{2.5%l} @c{a pinch} @d{1/0} @e{}")

      assert [a, b, c, d, e] = recipe.ingredients
      assert Decimal.eq?(Decimal.round(a.quantity, 4), Decimal.new("0.3333"))
      assert {b.canonical_unit, b.dimension, b.scalable} == {"l", :volume, true}
      assert {c.quantity, c.scalable, c.dimension} == {"a pinch", false, nil}
      assert d.quantity == "1/0"
      assert {e.quantity, e.dimension} == {nil, nil}
      assert messages(recipe) == [{1, "1/0 divides by zero, so it was kept as text."}]
    end

    test "an unclosed note and a nameless ingredient are text" do
      assert [%Ingredient{name: "salt", note: nil}, %Text{value: "(to taste and @{1} more"}] =
               only_step("@salt{}(to taste and @{1} more")
    end

    test "counted items and unknown units" do
      recipe = Cooklang.parse("@eggs{3} @chilli{2%items} @thyme{2%Sprigs.}")

      assert [eggs, chilli, thyme] = recipe.ingredients
      assert {eggs.key, eggs.canonical_unit, eggs.dimension} == {"egg", nil, :count}
      assert {chilli.canonical_unit, chilli.dimension} == {nil, :count}
      assert {thyme.canonical_unit, thyme.dimension} == {"sprig", nil}
    end

    test "cookware and timers are collected; cookware units are ignored with a warning" do
      recipe = Cooklang.parse("Use #pot{2%kg}, ~{10%min} and ~eggs{3%minutes} then ~rest")

      assert [%Cookware{name: "pot", quantity: two}] = recipe.cookware
      assert Decimal.eq?(two, 2)

      assert [%Timer{name: nil, unit: "min"}, %Timer{name: "eggs"}, %Timer{name: "rest"}] =
               recipe.timers

      assert messages(recipe) == [{1, "Cookware has no units, so \"kg\" on pot was ignored."}]
    end

    test "the ingredients list follows the steps, across sections" do
      recipe = Cooklang.parse("@a\n\n= Two\n@b and @?c{}")

      assert Enum.map(recipe.ingredients, &{&1.name, &1.optional}) == [
               {"a", false},
               {"b", false},
               {"c", true}
             ]
    end
  end

  describe "normalising" do
    alias Mealplan.Cooklang.Normalise

    test "names become singular merge keys" do
      pairs = [
        {"Tomatoes", "tomato"},
        {"cherries", "cherry"},
        {"peaches", "peach"},
        {"glasses", "glass"},
        {"bay leaves", "bay leaf"},
        {"red chillies", "red chilli"},
        {"cookies", "cookie"},
        {"olives", "olive"},
        {"hummus", "hummus"},
        {"molasses", "molasses"},
        {"peas", "pea"},
        {"egg", "egg"},
        {"oil", "oil"},
        {"", ""}
      ]

      for {name, key} <- pairs, do: assert(Normalise.key(name) == key, name)
    end

    test "units" do
      assert Normalise.unit("Tablespoons", nil) == {"tbsp", :volume}
      assert Normalise.unit("fl  oz", nil) == {"fl oz", :volume}
      assert Normalise.unit("KG", nil) == {"kg", :mass}
      assert Normalise.unit("pieces", Decimal.new(2)) == {nil, :count}
      assert Normalise.unit("Cloves", nil) == {"clove", nil}
      assert Normalise.unit(nil, "few") == {nil, nil}
    end

    test "an empty unit is no unit" do
      assert [%Ingredient{unit: nil, dimension: :count}] =
               Cooklang.parse("@salt{1% }").ingredients
    end
  end

  test "a paragraph with nothing left in it isn't a step" do
    assert Cooklang.parse("\\\n\nMix.").sections == [
             %Section{blocks: [%Step{items: [%Text{value: "Mix."}]}]}
           ]
  end

  describe "metadata" do
    test "front matter: values, quotes, lists and servings" do
      source = """
      ---
      title: "Pancakes"
      servings: 4 people
      source: https://example.com/pancakes
      tags: [breakfast, 'sweet']
      note: [not a list
      diet:
        - vegetarian
        - quick
      # a comment
      ---
      Mix.
      """

      recipe = Cooklang.parse(source)

      assert recipe.metadata == %{
               "title" => "Pancakes",
               "servings" => "4 people",
               "source" => "https://example.com/pancakes",
               "tags" => ["breakfast", "sweet"],
               "note" => "[not a list",
               "diet" => ["vegetarian", "quick"]
             }

      assert recipe.servings == 4
      assert recipe.warnings == []
    end

    test "unreadable lines warn; an unclosed block is text" do
      recipe = Cooklang.parse("---\nnested:\n  key: value\njust words\n---\nMix.")

      assert messages(recipe) == [
               {3, ~s(Couldn't read this metadata line; use "key: value".)},
               {4, ~s(Couldn't read this metadata line; use "key: value".)}
             ]

      assert recipe.metadata == %{"nested" => ""}

      recipe = Cooklang.parse("---\ntitle: x\nMix.")
      assert [{1, "The metadata block is never closed with ---."}] = messages(recipe)
      assert recipe.metadata == %{}
    end

    test ">> lines are metadata too and win over front matter" do
      recipe = Cooklang.parse("---\nserves: 2\n---\n>> serves: 6\n>> nonsense\nMix.")

      assert recipe.metadata == %{"serves" => "6"}
      assert recipe.servings == 6
      assert [{5, _unreadable}] = messages(recipe)
    end

    test "servings must start with a positive number" do
      assert Cooklang.parse("---\nservings: some\n---").servings == nil
      assert Cooklang.parse("---\nservings: 0\n---").servings == nil
      assert Cooklang.parse("---\nservings: [3, 4]\n---").servings == 3
    end
  end

  test "invalid UTF-8 and a byte order mark are handled" do
    byte_order_mark = <<0xEF, 0xBB, 0xBF>>
    recipe = Cooklang.parse(byte_order_mark <> "Add @salt " <> <<0xFF>>)

    assert [%Text{value: "Add "}, %Ingredient{name: "salt"}, %Text{value: " �"}] =
             recipe
             |> Map.fetch!(:sections)
             |> hd()
             |> Map.fetch!(:blocks)
             |> hd()
             |> Map.fetch!(:items)

    assert [%Warning{line: nil}] = recipe.warnings
  end

  describe "properties" do
    @fragments [
      "@",
      "#",
      "~",
      "?",
      "{",
      "}",
      "%",
      "(",
      ")",
      "--",
      "[-",
      "-]",
      "-",
      "\n",
      "\n\n",
      "\r\n",
      "---\n",
      ">",
      ">>",
      "=",
      "\\",
      ":",
      " ",
      <<0xE2, 0x80, 0x89>>,
      "⸫",
      "salt",
      "big pan",
      "1/2",
      "0/0",
      "01/2",
      "2.5",
      "g",
      "🧂",
      "é"
    ]

    defp cooklangish do
      gen all parts <- list_of(member_of(@fragments), max_length: 60) do
        Enum.join(parts)
      end
    end

    property "never raises, on any text" do
      check all source <- one_of([cooklangish(), string(:printable), binary()]), max_runs: 500 do
        assert %Recipe{} = recipe = Cooklang.parse(source)

        steps =
          for %Section{blocks: blocks} <- recipe.sections, %Step{} = step <- blocks, do: step

        step_items = Enum.flat_map(steps, & &1.items)

        # The flat lists are exactly the components in the steps.
        assert recipe.ingredients == Enum.filter(step_items, &is_struct(&1, Ingredient))

        assert length(recipe.cookware) + length(recipe.timers) + length(recipe.ingredients) ==
                 Enum.count(step_items, &(not is_struct(&1, Text)))

        # Steps aren't empty, and their text is merged and never empty.
        refute Enum.any?(steps, &(&1.items == []))
        refute Enum.any?(step_items, &match?(%Text{value: ""}, &1))

        for %Step{items: items} <- steps do
          refute items
                 |> Enum.chunk_every(2, 1, :discard)
                 |> Enum.any?(&match?([%Text{}, %Text{}], &1))
        end
      end
    end
  end
end
