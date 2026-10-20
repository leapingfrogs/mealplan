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
      order_by: [asc: fragment("lower(?)", r.name), asc: r.inserted_at],
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
