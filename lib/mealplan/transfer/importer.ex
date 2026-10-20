defmodule Mealplan.Transfer.Importer do
  @moduledoc """
  Matches a `Mealplan.Transfer.Bundle` against the household and applies
  the owner's choices (iteration 2 design, "Matching and choices").
  """
  import Ecto.Query

  alias Mealplan.Accounts.Scope
  alias Mealplan.Households
  alias Mealplan.Households.Household
  alias Mealplan.Meals
  alias Mealplan.Meals.Meal
  alias Mealplan.RateLimit
  alias Mealplan.Recipes
  alias Mealplan.Recipes.Recipe
  alias Mealplan.Repo
  alias Mealplan.Transfer.Bundle
  alias Mealplan.Transfer.CookFile
  alias Mealplan.Transfer.Import
  alias Mealplan.Transfer.ImportItem

  @imports_per_hour 5

  ## Planning

  @doc """
  Matches the bundle's recipes and meals by name (ignoring case) against
  the household's active ones and resolves meal references. New items are
  added and matches skipped unless the owner chooses otherwise.
  """
  def plan(%Scope{household: %Household{} = household} = scope, %Bundle{} = bundle) do
    recipes_by_name = by_name(Recipes.list_recipes(scope))

    meals_by_name =
      by_name(
        Repo.all(from m in Meal, where: m.household_id == ^household.id and is_nil(m.archived_at))
      )

    recipes =
      bundle.recipes
      |> Enum.with_index()
      |> Enum.map(fn {imported, index} ->
        "recipe-#{index}"
        |> item(imported, Map.get(recipes_by_name, String.downcase(imported.name)))
        |> Map.put(:servings, servings(imported.servings, household.usually_feeding))
      end)

    meals =
      bundle.meals
      |> Enum.with_index()
      |> Enum.map(fn {imported, index} ->
        "meal-#{index}"
        |> item(imported, Map.get(meals_by_name, String.downcase(imported.name)))
        |> Map.put(
          :references,
          Enum.map(imported.references, &resolve(&1, recipes, recipes_by_name))
        )
      end)

    %Import{recipes: recipes, meals: meals, problems: bundle.problems}
  end

  defp by_name(rows) do
    rows |> Enum.reverse() |> Map.new(&{String.downcase(&1.name), &1})
  end

  defp item(key, imported, existing) do
    %ImportItem{
      key: key,
      imported: imported,
      existing: existing,
      action: if(existing, do: :skip, else: :add)
    }
  end

  defp servings(nil, usual), do: usual
  defp servings(servings, _usual), do: servings |> max(1) |> min(100)

  # A path reference matches an imported recipe at that path, or ending in
  # it (zips often wrap everything in a folder); failing that, one of ours
  # whose name or file name is the last part. A name reference matches an
  # imported recipe by name, then one of ours.
  defp resolve({:path, path}, recipes, ours) do
    match =
      Enum.find(
        recipes,
        &(&1.imported.path == path or String.ends_with?(&1.imported.path, "/" <> path))
      )

    last = path |> String.split("/") |> List.last()

    cond do
      match -> {:imported, match.key}
      existing = Map.get(ours, last) || find_by_file_name(ours, last) -> {:existing, existing}
      true -> {:missing, path}
    end
  end

  defp resolve({:name, name}, recipes, ours) do
    key = String.downcase(name)

    cond do
      match = Enum.find(recipes, &(String.downcase(&1.imported.name) == key)) ->
        {:imported, match.key}

      existing = Map.get(ours, key) ->
        {:existing, existing}

      true ->
        {:missing, name}
    end
  end

  defp find_by_file_name(ours, file_name) do
    Enum.find_value(ours, fn {_name, recipe} ->
      if String.downcase(CookFile.file_name(recipe.name)) == file_name, do: recipe
    end)
  end

  ## Applying

  @doc """
  Applies the import with `choices` (`%{key => action}`, string or atom
  actions; anything not chosen keeps its default). All or nothing. Returns a
  summary of what was added, replaced and skipped.
  """
  def apply(%Scope{household: %Household{id: household_id}} = scope, %Import{} = import, choices) do
    cond do
      not Households.owner?(scope) ->
        {:error, :unauthorized}

      rate_limited?(household_id) ->
        {:error, :rate_limited}

      true ->
        import = with_choices(import, choices)
        Repo.transact(fn -> apply_all(scope, import) end)
    end
  end

  def apply(%Scope{}, %Import{}, _choices), do: {:error, :unauthorized}

  defp apply_all(scope, import) do
    with {:ok, recipe_ids, recipe_counts} <- apply_recipes(scope, import.recipes),
         {:ok, meal_counts} <- apply_meals(scope, import.meals, recipe_ids) do
      {:ok, %{recipes: recipe_counts, meals: meal_counts}}
    end
  end

  defp rate_limited?(household_id) do
    match?(
      {:deny, _},
      RateLimit.hit("imports:#{household_id}", to_timeout(hour: 1), @imports_per_hour)
    )
  end

  defp with_choices(import, choices) do
    choose = fn item ->
      chosen = choices |> Map.get(item.key) |> to_action()
      if chosen in ImportItem.actions(item), do: %{item | action: chosen}, else: item
    end

    %{import | recipes: Enum.map(import.recipes, choose), meals: Enum.map(import.meals, choose)}
  end

  @actions ~w(add skip replace keep_both leave_out)a
  defp to_action(action) when action in @actions, do: action

  defp to_action(action) when is_binary(action),
    do: Enum.find(@actions, &(Atom.to_string(&1) == action))

  defp to_action(_none), do: nil

  # Returns the recipe id each imported recipe ended up as (ours when
  # skipped; nil when left out) and counts.
  defp apply_recipes(scope, items) do
    taken = scope |> Recipes.list_recipes() |> MapSet.new(&String.downcase(&1.name))

    items
    |> Enum.reduce_while({:ok, %{}, counts(), taken}, fn item, {:ok, ids, counts, taken} ->
      case apply_recipe(scope, item, taken) do
        {:ok, id, outcome, name} ->
          {:cont,
           {:ok, Map.put(ids, item.key, id), bump(counts, outcome),
            MapSet.put(taken, String.downcase(name))}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, ids, counts, _taken} -> {:ok, ids, counts}
      error -> error
    end
  end

  defp apply_recipe(scope, %ImportItem{action: action, imported: imported} = item, taken) do
    attrs = %{source: imported.source, servings: item.servings}

    case action do
      :add ->
        create_recipe(scope, Map.put(attrs, :name, imported.name), :added)

      :keep_both ->
        create_recipe(scope, Map.put(attrs, :name, free_name(imported.name, taken)), :added)

      :replace ->
        update_recipe(scope, item.existing, attrs)

      :skip ->
        {:ok, item.existing.id, :skipped, item.existing.name}

      :leave_out ->
        {:ok, nil, :left_out, ""}
    end
  end

  defp create_recipe(scope, attrs, outcome) do
    with {:ok, recipe} <- Recipes.create_recipe(scope, attrs),
         do: {:ok, recipe.id, outcome, recipe.name}
  end

  defp update_recipe(scope, existing, attrs) do
    with {:ok, recipe} <- Recipes.update_recipe(scope, existing, attrs),
         do: {:ok, recipe.id, :replaced, recipe.name}
  end

  defp apply_meals(scope, items, recipe_ids) do
    taken =
      from(m in Meal,
        where: m.household_id == ^scope.household.id and is_nil(m.archived_at),
        select: fragment("lower(?)", m.name)
      )
      |> Repo.all()
      |> MapSet.new()

    items
    |> Enum.reduce_while({:ok, counts(), taken}, fn item, {:ok, counts, taken} ->
      ids = item.references |> Enum.map(&recipe_id(&1, recipe_ids)) |> Enum.reject(&is_nil/1)

      case apply_meal(scope, item, ids, taken) do
        {:ok, outcome, name} ->
          {:cont, {:ok, bump(counts, outcome), MapSet.put(taken, String.downcase(name))}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, counts, _taken} -> {:ok, counts}
      error -> error
    end
  end

  defp recipe_id({:imported, key}, recipe_ids), do: Map.get(recipe_ids, key)
  defp recipe_id({:existing, %Recipe{id: id}}, _recipe_ids), do: id
  defp recipe_id({:missing, _label}, _recipe_ids), do: nil

  defp apply_meal(
         scope,
         %ImportItem{action: action, imported: imported} = item,
         recipe_ids,
         taken
       ) do
    case action do
      :add -> create_meal(scope, free_name(imported.name, taken), recipe_ids)
      :keep_both -> create_meal(scope, free_name(imported.name, taken), recipe_ids)
      :replace -> replace_meal(scope, item.existing, recipe_ids)
      :skip -> {:ok, :skipped, item.existing.name}
      :leave_out -> {:ok, :left_out, ""}
    end
  end

  defp create_meal(scope, name, recipe_ids) do
    with {:ok, meal} <- Meals.create_meal(scope, %{name: name}),
         {:ok, _meal} <- Meals.set_recipes(scope, meal.id, recipe_ids) do
      {:ok, :added, meal.name}
    end
  end

  defp replace_meal(scope, existing, recipe_ids) do
    with {:ok, _meal} <- Meals.set_recipes(scope, existing.id, recipe_ids),
         do: {:ok, :replaced, existing.name}
  end

  # The name, or "Name (2)", "Name (3)"... if taken (ignoring case).
  defp free_name(name, taken) do
    base = String.slice(name, 0, 110)

    1
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base} (#{n})"
    end)
    |> Enum.find(&(not MapSet.member?(taken, String.downcase(&1))))
  end

  defp counts, do: %{added: 0, replaced: 0, skipped: 0, left_out: 0}
  defp bump(counts, outcome), do: Map.update!(counts, outcome, &(&1 + 1))
end
