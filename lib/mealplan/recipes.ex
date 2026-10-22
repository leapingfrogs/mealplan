defmodule Mealplan.Recipes do
  @moduledoc """
  A household's recipes. Every function takes the caller's
  `Mealplan.Accounts.Scope` and only touches that scope's household; any
  member may create and edit recipes.

  Changes are broadcast to the household as `{:recipe_changed, recipe_id}`.
  """
  import Ecto.Query

  alias Mealplan.Accounts.Scope
  alias Mealplan.Accounts.User
  alias Mealplan.Cooklang
  alias Mealplan.Households
  alias Mealplan.Households.Household
  alias Mealplan.Meals
  alias Mealplan.Meals.Meal
  alias Mealplan.Meals.MealRecipe
  alias Mealplan.Planning
  alias Mealplan.Planning.Leftover
  alias Mealplan.Planning.PlannedMeal
  alias Mealplan.Recipes.Recipe
  alias Mealplan.Recipes.RecipeIngredient
  alias Mealplan.Repo

  @doc """
  Lists the household's active recipes by name, each with its
  `ingredient_count` (distinct ingredients). `search` matches the recipe
  name or any ingredient, ignoring case.
  """
  def list_recipes(%Scope{household: %Household{id: household_id}}, search \\ "") do
    ingredient_count =
      from i in RecipeIngredient,
        where: i.recipe_id == parent_as(:recipe).id,
        select: count(i.key, :distinct)

    from(r in Recipe,
      as: :recipe,
      where: r.household_id == ^household_id and is_nil(r.archived_at),
      order_by: ^by_name(),
      select: %{r | ingredient_count: subquery(ingredient_count)}
    )
    |> search(String.trim(search || ""))
    |> Repo.all()
  end

  defp search(query, ""), do: query

  defp search(query, term) do
    pattern = "%" <> escape_like(term) <> "%"

    ingredient_matches =
      from i in RecipeIngredient,
        where:
          i.recipe_id == parent_as(:recipe).id and
            (ilike(i.name, ^pattern) or ilike(i.key, ^pattern))

    where(query, [r], ilike(r.name, ^pattern) or exists(ingredient_matches))
  end

  defp escape_like(term), do: String.replace(term, ~w(\\ % _), &("\\" <> &1))

  @doc """
  Gets one of the household's recipes with its ingredients. Raises
  `Ecto.NoResultsError` (a 404) for anything else.
  """
  def get_recipe!(%Scope{household: %Household{id: household_id}}, id) do
    Recipe
    |> where(household_id: ^household_id)
    |> preload(:ingredients)
    |> Repo.get!(id)
  end

  @doc "Like `get_recipe!/2`, but nil for a missing, malformed or foreign id."
  def get_recipe(%Scope{household: %Household{id: household_id}}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Recipe |> where(household_id: ^household_id) |> preload(:ingredients) |> Repo.get(id)

      :error ->
        nil
    end
  end

  @doc "Returns a changeset for the recipe form."
  def change_recipe(%Recipe{} = recipe, attrs \\ %{}), do: Recipe.changeset(recipe, attrs)

  @doc "A new recipe for the household, serving its usual number of people."
  def new_recipe(%Scope{household: %Household{} = household}) do
    %Recipe{household_id: household.id, servings: household.usually_feeding}
  end

  @doc "Creates a recipe and its ingredient rows."
  def create_recipe(
        %Scope{household: %Household{id: household_id}, user: %User{id: user_id}} = scope,
        attrs
      ) do
    %Recipe{household_id: household_id, created_by_id: user_id}
    |> Recipe.changeset(attrs)
    |> save(scope, &Repo.insert/1)
  end

  @doc "Updates a recipe and rebuilds its ingredient rows from the source."
  def update_recipe(
        %Scope{household: %Household{id: household_id}} = scope,
        %Recipe{household_id: household_id} = recipe,
        attrs
      ) do
    recipe
    |> Recipe.changeset(attrs)
    |> save(scope, &Repo.update/1)
  end

  def update_recipe(%Scope{}, %Recipe{}, _attrs), do: {:error, :not_found}

  ## Deleting and archiving

  @doc """
  What deleting a recipe will do: the active `meals` it will be taken out
  of, and whether it will be archived (`archive?`) because a plan before
  today used it, rather than deleted.
  """
  def deletion_preview(%Scope{} = scope, %Recipe{} = recipe) do
    meals =
      Repo.all(
        from m in Meal,
          join: mr in assoc(m, :meal_recipes),
          where: mr.recipe_id == ^recipe.id and is_nil(m.archived_at),
          order_by: fragment("lower(?)", m.name)
      )

    %{meals: meals, archive?: used_before?(recipe, Planning.today(scope))}
  end

  @doc """
  Deletes a recipe: it is taken out of every meal, and leftover links for
  it from today on go. If a plan before today used it, it is archived
  instead and the meals those plans used keep it in their history (see
  `Mealplan.Meals.recipes_on/3`); otherwise it is deleted. Returns
  `{:ok, :archived}` or `{:ok, :deleted}`.
  """
  def delete_recipe(
        %Scope{household: %Household{id: household_id}} = scope,
        %Recipe{household_id: household_id} = recipe
      ) do
    today = Planning.today(scope)

    result =
      Repo.transact(fn ->
        archive? = used_before?(recipe, today)

        upcoming = from pm in PlannedMeal, where: pm.date >= ^today, select: pm.id

        {_count, _} =
          Repo.delete_all(
            from l in Leftover,
              where: l.recipe_id == ^recipe.id and l.planned_meal_id in subquery(upcoming)
          )

        :ok =
          Meals.take_out(
            scope,
            from(mr in MealRecipe, where: mr.recipe_id == ^recipe.id and is_nil(mr.removed_on))
          )

        if archive? do
          {:ok, _recipe} =
            recipe
            |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second))
            |> Repo.update()

          {:ok, :archived}
        else
          {:ok, _recipe} = Repo.delete(recipe)
          {:ok, :deleted}
        end
      end)

    with {:ok, _outcome} <- result do
      :ok = Households.broadcast(scope, {:recipe_changed, recipe.id})
      :ok = Households.broadcast(scope, {:plan_changed, Planning.week_start(today)})
      result
    end
  end

  def delete_recipe(%Scope{}, %Recipe{}), do: {:error, :not_found}

  defp used_before?(recipe, today) do
    Repo.exists?(
      from pm in PlannedMeal,
        join: mr in MealRecipe,
        on: mr.meal_id == pm.meal_id,
        where:
          mr.recipe_id == ^recipe.id and pm.date < ^today and
            (is_nil(mr.removed_on) or mr.removed_on > pm.date)
    ) or
      Repo.exists?(
        from l in Leftover,
          join: pm in assoc(l, :planned_meal),
          where: l.recipe_id == ^recipe.id and pm.date < ^today
      )
  end

  # By name ignoring case; names that differ only in case (Soup, soup) in
  # byte order, so exports always number them the same way.
  defp by_name do
    [
      asc: dynamic([r], fragment("lower(?)", r.name)),
      asc: dynamic([r], fragment("? COLLATE \"C\"", r.name)),
      asc: dynamic([r], r.inserted_at),
      asc: dynamic([r], r.id)
    ]
  end

  @doc "Lists the household's archived recipes by name."
  def list_archived_recipes(%Scope{household: %Household{id: household_id}}) do
    Repo.all(
      from r in Recipe,
        where: r.household_id == ^household_id and not is_nil(r.archived_at),
        order_by: ^by_name()
    )
  end

  @doc "Restores an archived recipe to lists and pickers."
  def restore_recipe(%Scope{household: %Household{id: household_id}} = scope, recipe_id) do
    with {:ok, id} <- Ecto.UUID.cast(recipe_id),
         %Recipe{} = recipe <-
           Repo.one(
             from r in Recipe,
               where:
                 r.id == ^id and r.household_id == ^household_id and not is_nil(r.archived_at)
           ),
         {:ok, recipe} <- recipe |> Ecto.Changeset.change(archived_at: nil) |> Repo.update() do
      :ok = Households.broadcast(scope, {:recipe_changed, recipe.id})
      {:ok, recipe}
    else
      _ -> {:error, :not_found}
    end
  end

  defp save(changeset, scope, write) do
    result =
      Repo.transact(fn ->
        with {:ok, recipe} <- write.(changeset) do
          {:ok, replace_ingredients(recipe)}
        end
      end)

    with {:ok, recipe} <- result do
      :ok = Households.broadcast(scope, {:recipe_changed, recipe.id})
      {:ok, recipe}
    end
  end

  defp replace_ingredients(recipe) do
    _ = Repo.delete_all(from i in RecipeIngredient, where: i.recipe_id == ^recipe.id)

    rows =
      recipe.source
      |> Cooklang.parse()
      |> Map.fetch!(:ingredients)
      |> Enum.with_index()
      |> Enum.map(fn {ingredient, position} ->
        RecipeIngredient.from_parsed(ingredient, recipe, position)
      end)

    {_count, _rows} = Repo.insert_all(RecipeIngredient, rows)
    Repo.preload(recipe, :ingredients, force: true)
  end
end
