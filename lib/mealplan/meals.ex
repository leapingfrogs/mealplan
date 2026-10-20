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
  alias Mealplan.Planning
  alias Mealplan.Planning.PlannedMeal
  alias Mealplan.Recipes.Recipe
  alias Mealplan.Repo

  @doc """
  Lists the household's active meals by name, each with its `recipe_count`.
  `search` matches the meal's name or any of its recipes' names.
  """
  def list_meals(%Scope{household: %Household{id: household_id}}, search \\ "") do
    recipe_count =
      from mr in current_recipes(), where: mr.meal_id == parent_as(:meal).id, select: count()

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
      from mr in current_recipes(),
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
        Repo.one(
          from mr in current_recipes(), where: mr.meal_id == ^meal.id, select: max(mr.position)
        )

      %MealRecipe{
        household_id: household_id,
        meal_id: meal.id,
        recipe_id: recipe.id,
        position: (last || -1) + 1
      }
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.unique_constraint([:meal_id, :recipe_id],
        name: :meal_recipes_current_index
      )
      |> Repo.insert()
      |> case do
        {:ok, _meal_recipe} -> broadcast({:ok, meal}, scope)
        {:error, _changeset} -> {:error, :already_in_meal}
      end
    end
  end

  @doc """
  Removes a recipe from a meal (the recipe itself is untouched). If the meal
  was planned before today the link is kept with `removed_on` set, so those
  past plans still have the recipe; otherwise it is deleted.
  """
  def remove_recipe(%Scope{} = scope, meal_id, recipe_id) do
    with {:ok, meal} <- fetch_meal(scope, meal_id),
         {:ok, recipe_id} <- Ecto.UUID.cast(recipe_id) do
      :ok =
        take_out(
          scope,
          from(mr in current_recipes(),
            where: mr.meal_id == ^meal.id and mr.recipe_id == ^recipe_id
          )
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
            from(mr in current_recipes(),
              where: mr.meal_id == ^meal.id and mr.recipe_id == ^recipe_id
            ),
            set: [position: position]
          )
        end)

        {:ok, recipe_ids}
      end)

    :ok
  end

  ## Deleting and archiving

  @doc """
  What deleting a meal will do: the `upcoming` planned meals (today on,
  with their slots) that will be removed, and whether it will be archived
  (`archive?`) because it was planned before today, rather than deleted.
  """
  def deletion_preview(%Scope{} = scope, %Meal{} = meal) do
    today = Planning.today(scope)

    upcoming =
      Repo.all(
        from pm in PlannedMeal,
          join: s in assoc(pm, :meal_slot),
          where: pm.meal_id == ^meal.id and pm.date >= ^today,
          order_by: [asc: pm.date, asc: s.position],
          preload: [meal_slot: s]
      )

    %{upcoming: upcoming, archive?: planned_before?(meal, today)}
  end

  @doc """
  Deletes a meal: its planned meals from today on are removed (with their
  leftover links). If it was planned before today it is archived instead,
  so history keeps it; otherwise it is deleted. Returns `{:ok, :archived}`
  or `{:ok, :deleted}`.
  """
  def delete_meal(
        %Scope{household: %Household{id: household_id}} = scope,
        %Meal{household_id: household_id} = meal
      ) do
    today = Planning.today(scope)

    result =
      Repo.transact(fn ->
        weeks =
          Repo.all(
            from pm in PlannedMeal,
              where: pm.meal_id == ^meal.id and pm.date >= ^today,
              select: pm.date
          )

        {_count, _} =
          Repo.delete_all(
            from pm in PlannedMeal, where: pm.meal_id == ^meal.id and pm.date >= ^today
          )

        outcome =
          if planned_before?(meal, today) do
            {:ok, _meal} =
              meal
              |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second))
              |> Repo.update()

            :archived
          else
            {:ok, _meal} = Repo.delete(meal)
            :deleted
          end

        {:ok, {outcome, weeks}}
      end)

    with {:ok, {outcome, dates}} <- result do
      :ok = Households.broadcast(scope, {:meal_changed, meal.id})

      for week <- dates |> Enum.map(&Planning.week_start/1) |> Enum.uniq() do
        :ok = Households.broadcast(scope, {:plan_changed, week})
      end

      {:ok, outcome}
    end
  end

  def delete_meal(%Scope{}, %Meal{}), do: {:error, :not_found}

  defp planned_before?(meal, today) do
    Repo.exists?(from pm in PlannedMeal, where: pm.meal_id == ^meal.id and pm.date < ^today)
  end

  @doc "Lists the household's archived meals by name."
  def list_archived_meals(%Scope{household: %Household{id: household_id}}) do
    Repo.all(
      from m in Meal,
        where: m.household_id == ^household_id and not is_nil(m.archived_at),
        order_by: fragment("lower(?)", m.name)
    )
  end

  @doc """
  Restores an archived meal to lists and pickers. Refused with a changeset
  error if an active meal has taken its name meanwhile.
  """
  def restore_meal(%Scope{household: %Household{id: household_id}} = scope, meal_id) do
    with {:ok, id} <- Ecto.UUID.cast(meal_id),
         %Meal{} = meal <-
           Repo.one(
             from m in Meal,
               where:
                 m.id == ^id and m.household_id == ^household_id and not is_nil(m.archived_at)
           ) do
      meal
      |> Ecto.Changeset.change(archived_at: nil)
      |> Ecto.Changeset.unique_constraint(:name,
        name: :meals_household_id_name_index,
        message: "is already a meal"
      )
      |> Repo.update()
      |> broadcast(scope)
    else
      _ -> {:error, :not_found}
    end
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
         from mr in current_recipes(),
           where: mr.meal_id == ^meal.id and mr.recipe_id == ^recipe.id
       ),
       do: {:error, :already_in_meal},
       else: :ok
  end

  defp current_recipes, do: from(mr in MealRecipe, where: is_nil(mr.removed_on))

  @doc """
  Takes recipes out of meals (`links` is a query of current meal recipes):
  links that past plans of their meal relied on are kept with `removed_on`
  set to today; the rest are deleted.
  """
  def take_out(%Scope{} = scope, links) do
    today = Planning.today(scope)

    kept =
      Repo.all(
        from mr in links,
          join: pm in PlannedMeal,
          on: pm.meal_id == mr.meal_id and pm.date < ^today,
          distinct: true,
          select: mr.id
      )

    {_count, _} =
      Repo.update_all(from(mr in MealRecipe, where: mr.id in ^kept), set: [removed_on: today])

    {_count, _} = Repo.delete_all(from mr in links, where: mr.id not in ^kept)
    :ok
  end

  @doc """
  The recipes a meal had on `date`: what a planned meal on that date was
  made of, including recipes since taken out of the meal or archived. (A
  recipe added to the meal later counts too; only removals are dated.)
  """
  def recipes_on(%Scope{household: %Household{id: household_id}}, meal_id, %Date{} = date) do
    Repo.all(
      from mr in MealRecipe,
        join: m in assoc(mr, :meal),
        join: r in assoc(mr, :recipe),
        where:
          mr.meal_id == ^meal_id and m.household_id == ^household_id and
            (is_nil(mr.removed_on) or mr.removed_on > ^date),
        order_by: mr.position,
        select: r
    )
  end

  defp broadcast({:ok, %Meal{} = meal}, scope) do
    :ok = Households.broadcast(scope, {:meal_changed, meal.id})
    {:ok, meal}
  end

  defp broadcast(error, _scope), do: error
end
