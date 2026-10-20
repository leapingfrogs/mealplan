defmodule Mealplan.Transfer do
  @moduledoc """
  Import and export of a household's recipes and meals (ADR 14).

  An export is a Cooklang recipe folder in a zip: `recipes/<name>.cook` for
  each active recipe, with its name and servings in the front matter, and
  `meals.menu` with a section per active meal listing its recipes. Owner
  only.
  """
  alias Mealplan.Accounts.Scope
  alias Mealplan.Households
  alias Mealplan.Households.Household
  alias Mealplan.Meals
  alias Mealplan.Planning
  alias Mealplan.Recipes
  alias Mealplan.Recipes.Recipe
  alias Mealplan.Repo
  alias Mealplan.Transfer.CookFile
  alias Mealplan.Transfer.Reader

  @doc """
  The household's active recipes and meals as `{file_name, zip_binary}`.
  """
  def export(%Scope{household: %Household{} = household} = scope) do
    if Households.owner?(scope) do
      recipes = Recipes.list_recipes(scope)
      file_names = recipes |> Enum.map(& &1.name) |> CookFile.unique_file_names()
      file_by_recipe = recipes |> Enum.map(& &1.id) |> Enum.zip(file_names) |> Map.new()
      today = Planning.today(scope)

      entries =
        Enum.zip_with(recipes, file_names, fn recipe, file_name ->
          {"recipes/#{file_name}.cook", cook_text(recipe)}
        end) ++ [{"meals.menu", meals_menu(scope, file_by_recipe, today)}]

      {:ok, {"mealplan-#{CookFile.file_name(household.name)}-#{today}.zip", zip(entries)}}
    else
      {:error, :unauthorized}
    end
  end

  def export(%Scope{}), do: {:error, :not_found}

  @doc """
  Reads uploaded `{file_name, binary}` pairs (`.zip`, `.cook`, `.menu`) into
  a `Mealplan.Transfer.Bundle`. Pure; never raises.
  """
  defdelegate read(uploads), to: Reader

  @doc "Import limits, for forms and messages."
  defdelegate limits(), to: Reader

  @doc "One recipe as `{file_name, cook_text}`. Owner only."
  def recipe_file(
        %Scope{household: %Household{id: household_id}} = scope,
        %Recipe{household_id: household_id} = recipe
      ) do
    if Households.owner?(scope),
      do: {:ok, {CookFile.file_name(recipe.name) <> ".cook", cook_text(recipe)}},
      else: {:error, :unauthorized}
  end

  def recipe_file(%Scope{}, %Recipe{}), do: {:error, :not_found}

  defp cook_text(recipe), do: CookFile.with_metadata(recipe.source, recipe.name, recipe.servings)

  # One section per meal, its recipes in order as references; a meal
  # without recipes is an empty section.
  defp meals_menu(scope, file_by_recipe, today) do
    sections =
      scope
      |> Meals.list_meals()
      |> Repo.preload(:meal_recipes)
      |> Enum.map(fn meal ->
        references =
          for %{recipe_id: id} <- meal.meal_recipes,
              file_name = Map.get(file_by_recipe, id),
              do: "@./recipes/#{file_name}{}"

        Enum.join(["= #{section_name(meal.name)}" | blank_then(references)], "\n")
      end)

    Enum.join(["---\nsource: Mealplan\nexported: #{today}\n---" | sections], "\n\n") <> "\n"
  end

  defp blank_then([]), do: []
  defp blank_then(lines), do: ["" | lines]

  # "=" at either end would be read as part of the section marker.
  defp section_name(name) do
    case name |> String.trim("=") |> String.trim() do
      "" -> "Meal"
      name -> name
    end
  end

  defp zip(entries) do
    files = for {path, content} <- entries, do: {String.to_charlist(path), content}
    {:ok, {_name, binary}} = :zip.create(~c"export.zip", files, [:memory])
    binary
  end
end
