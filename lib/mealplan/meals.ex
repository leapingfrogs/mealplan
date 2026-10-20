defmodule Mealplan.Meals do
  @moduledoc """
  A household's meals and the recipes in them. Every function takes the
  caller's `Mealplan.Accounts.Scope` and only touches that scope's
  household; any member may create and edit meals.

  Changes are broadcast to the household as `{:meal_changed, meal_id}`.
  """
  import Ecto.Query

  alias Mealplan.Accounts.Scope
  alias Mealplan.Accounts.User
  alias Mealplan.Households
  alias Mealplan.Households.Household
  alias Mealplan.Meals.Meal
  alias Mealplan.Meals.MealRecipe
  alias Mealplan.Recipes.Recipe
  alias Mealplan.Repo

  @doc """
  Lists the household's active meals by name, each with its `recipe_count`.
  `search` matches the meal's name or any of its recipes' names.
  """
  def list_meals(%Scope{household: %Household{id: household_id}}, search \\ "") do
    recipe_count =
      from mr in MealRecipe, where: mr.meal_id == parent_as(:meal).id, select: count()

    from(m in Meal,
      as: :meal,
      where: m.household_id == ^household_id and is_nil(m.archived_at),
      order_by: [asc: fragment("lower(?)", m.name), asc: m.inserted_at],
      select: %{m | recipe_count: subquery(recipe_count)}
    )
    |> search(String.trim(search || ""))
    |> Repo.all()
  end

  defp search(query, ""), do: query

  defp search(query, term) do
    pattern = "%" <> escape_like(term) <> "%"

    recipe_matches =
      from mr in MealRecipe,
        join: r in assoc(mr, :recipe),
        where: mr.meal_id == parent_as(:meal).id and ilike(r.name, ^pattern)

    where(query, [m], ilike(m.name, ^pattern) or exists(recipe_matches))
  end

  defp escape_like(term), do: String.replace(term, ~w(\\ % _), &("\\" <> &1))

  @doc """
  Gets one of the household's meals with its recipes in order. Raises
  `Ecto.NoResultsError` (a 404) for anything else.
  """
  def get_meal!(%Scope{household: %Household{id: household_id}}, id) do
    Meal
    |> where(household_id: ^household_id)
    |> preload(meal_recipes: :recipe)
    |> Repo.get!(id)
  end

  @doc "Returns a changeset for a meal's name."
  def change_meal(%Meal{} = meal \\ %Meal{}, attrs \\ %{}), do: Meal.changeset(meal, attrs)

  @doc "Creates an empty meal."
  def create_meal(
        %Scope{household: %Household{id: household_id}, user: %User{id: user_id}} = scope,
        attrs
      ) do
    %Meal{household_id: household_id, created_by_id: user_id}
    |> Meal.changeset(attrs)
    |> Repo.insert()
    |> broadcast(scope)
  end

  @doc "Renames a meal."
  def rename_meal(%Scope{} = scope, meal_id, attrs) do
    with {:ok, meal} <- fetch_meal(scope, meal_id) do
      meal |> Meal.changeset(attrs) |> Repo.update() |> broadcast(scope)
    end
  end

  @doc """
  Adds one of the household's active recipes to the end of a meal. A
  recipe is in a meal at most once.
  """
  def add_recipe(%Scope{household: %Household{id: household_id}} = scope, meal_id, recipe_id) do
    with {:ok, meal} <- fetch_meal(scope, meal_id),
         {:ok, recipe} <- fetch_recipe(household_id, recipe_id),
         :ok <- not_in_meal(meal, recipe) do
      last =
        Repo.one(from mr in MealRecipe, where: mr.meal_id == ^meal.id, select: max(mr.position))

      %MealRecipe{
        household_id: household_id,
        meal_id: meal.id,
        recipe_id: recipe.id,
        position: (last || -1) + 1
      }
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.unique_constraint([:meal_id, :recipe_id])
      |> Repo.insert()
      |> case do
        {:ok, _meal_recipe} -> broadcast({:ok, meal}, scope)
        {:error, _changeset} -> {:error, :already_in_meal}
      end
    end
  end

  @doc "Removes a recipe from a meal (the recipe itself is untouched)."
  def remove_recipe(%Scope{} = scope, meal_id, recipe_id) do
    with {:ok, meal} <- fetch_meal(scope, meal_id),
         {:ok, recipe_id} <- Ecto.UUID.cast(recipe_id) do
      {_count, _} =
        Repo.delete_all(
          from mr in MealRecipe, where: mr.meal_id == ^meal.id and mr.recipe_id == ^recipe_id
        )

      broadcast({:ok, meal}, scope)
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Moves a recipe one place earlier or later in a meal."
  def move_recipe(%Scope{} = scope, meal_id, recipe_id, direction)
      when direction in [:up, :down] do
    with {:ok, meal} <- fetch_meal(scope, meal_id) do
      ids =
        meal
        |> Repo.preload(:meal_recipes)
        |> Map.fetch!(:meal_recipes)
        |> Enum.map(& &1.recipe_id)

      index = Enum.find_index(ids, &(&1 == recipe_id))
      other = if direction == :up, do: index && index - 1, else: index && index + 1

      if index && other in 0..(length(ids) - 1)//1 do
        :ok =
          ids
          |> List.replace_at(index, Enum.at(ids, other))
          |> List.replace_at(other, recipe_id)
          |> set_positions(meal)

        broadcast({:ok, meal}, scope)
      else
        {:error, :not_found}
      end
    end
  end

  defp set_positions(recipe_ids, meal) do
    {:ok, _} =
      Repo.transact(fn ->
        recipe_ids
        |> Enum.with_index()
        |> Enum.each(fn {recipe_id, position} ->
          Repo.update_all(
            from(mr in MealRecipe, where: mr.meal_id == ^meal.id and mr.recipe_id == ^recipe_id),
            set: [position: position]
          )
        end)

        {:ok, recipe_ids}
      end)

    :ok
  end

  defp fetch_meal(%Scope{household: %Household{id: household_id}}, meal_id) do
    with {:ok, meal_id} <- Ecto.UUID.cast(meal_id),
         %Meal{} = meal <-
           Repo.one(
             from m in Meal,
               where:
                 m.id == ^meal_id and m.household_id == ^household_id and is_nil(m.archived_at)
           ) do
      {:ok, meal}
    else
      _ -> {:error, :not_found}
    end
  end

  defp fetch_recipe(household_id, recipe_id) do
    with {:ok, recipe_id} <- Ecto.UUID.cast(recipe_id),
         %Recipe{} = recipe <-
           Repo.one(
             from r in Recipe,
               where:
                 r.id == ^recipe_id and r.household_id == ^household_id and is_nil(r.archived_at)
           ) do
      {:ok, recipe}
    else
      _ -> {:error, :not_found}
    end
  end

  defp not_in_meal(meal, recipe) do
    if Repo.exists?(
         from mr in MealRecipe, where: mr.meal_id == ^meal.id and mr.recipe_id == ^recipe.id
       ),
       do: {:error, :already_in_meal},
       else: :ok
  end

  defp broadcast({:ok, %Meal{} = meal}, scope) do
    :ok = Households.broadcast(scope, {:meal_changed, meal.id})
    {:ok, meal}
  end

  defp broadcast(error, _scope), do: error
end
