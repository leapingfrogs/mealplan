defmodule Mealplan.Planning do
  @moduledoc """
  Week plans: planned meals, leftovers and skipped slots, and the servings
  maths the shopping list builds on.

  Dates are household-local: "today" and week boundaries come from the
  household's time zone. Weeks run Monday to Sunday. Every function takes
  the caller's `Mealplan.Accounts.Scope` and only touches its household; any
  member may plan. Changes are broadcast to the household as
  `{:plan_changed, week_start}` for each affected week.

  ## Cooked servings

  For each recipe in a planned meal that isn't itself leftovers:

      cooked = planned servings + servings of later meals eating it as leftovers
      scale  = cooked / recipe servings

  ## Leftovers

  A recipe of a planned meal can be eaten as leftovers of an earlier planned
  meal (earlier date, or the same date in an earlier slot) that also contains
  the recipe and cooks it fresh. The source may be up to 14 days earlier
  (`leftover_days/0`), in an earlier week, to allow for food frozen for
  later. Moving or changing either meal removes leftover links that no longer
  satisfy this.
  """
  import Ecto.Query

  alias Mealplan.Accounts.Scope
  alias Mealplan.Households
  alias Mealplan.Households.Household
  alias Mealplan.Households.MealSlot
  alias Mealplan.Meals
  alias Mealplan.Meals.Meal
  alias Mealplan.Meals.MealRecipe
  alias Mealplan.Planning.Leftover
  alias Mealplan.Planning.PlannedMeal
  alias Mealplan.Planning.SlotSkip
  alias Mealplan.Planning.Week
  alias Mealplan.Recipes.Recipe
  alias Mealplan.Repo

  @leftover_days 14

  @doc "How many days before a meal its leftovers may have been cooked."
  def leftover_days, do: @leftover_days

  ## Dates and weeks

  @doc "Today's date in the household's time zone."
  def today(%Scope{household: %Household{time_zone: time_zone}}, now \\ DateTime.utc_now()) do
    now |> DateTime.shift_zone!(time_zone) |> DateTime.to_date()
  end

  @doc "The Monday starting the week that contains `date`."
  def week_start(%Date{} = date), do: Date.beginning_of_week(date, :monday)

  @doc "The Monday of the household's current week."
  def current_week(%Scope{} = scope, now \\ DateTime.utc_now()),
    do: scope |> today(now) |> week_start()

  @doc """
  The week the planner opens on: the current week, or next week once the
  current one is fully planned.
  """
  def default_week(%Scope{} = scope, now \\ DateTime.utc_now()) do
    current = current_week(scope, now)
    if Week.fully_planned?(get_week(scope, current)), do: Date.add(current, 7), else: current
  end

  @doc "Loads the week containing `date` (see `Mealplan.Planning.Week`)."
  def get_week(%Scope{household: %Household{id: household_id}} = scope, %Date{} = date) do
    start = week_start(date)
    stop = Date.add(start, 6)
    slots = Households.list_meal_slots(scope)

    planned_meals =
      Repo.all(
        from pm in PlannedMeal,
          where: pm.household_id == ^household_id and pm.date >= ^start and pm.date <= ^stop,
          order_by: [asc: pm.date, asc: pm.position, asc: pm.inserted_at],
          preload: [
            :meal_slot,
            leftovers: [source_planned_meal: [:meal_slot, :meal]],
            leftovers_taken: [planned_meal: [:meal_slot, :meal]],
            meal: [meal_recipes: :recipe]
          ]
      )

    skips =
      Repo.all(
        from s in SlotSkip,
          where: s.household_id == ^household_id and s.date >= ^start and s.date <= ^stop
      )

    active = MapSet.new(slots, & &1.id)

    planned =
      planned_meals
      |> Enum.map(&{&1.date, &1.meal_slot_id})
      |> Enum.concat(Enum.map(skips, &{&1.date, &1.meal_slot_id}))
      |> Enum.uniq()
      |> Enum.count(fn {_date, slot_id} -> MapSet.member?(active, slot_id) end)

    %Week{
      start: start,
      days: Enum.to_list(Date.range(start, stop)),
      slots: slots,
      planned_meals: planned_meals,
      skips: skips,
      planned: planned,
      cells: 7 * length(slots)
    }
  end

  ## Cooked servings

  @doc """
  What to cook in a week: one entry per recipe cooked fresh in a planned
  meal, with `cooked_servings` (planned plus leftovers taken from it, even
  by meals in later weeks) and
  `scale` (cooked ÷ the recipe's servings, a `Decimal`). Recipes eaten as
  leftovers are left out; their servings count in their source.
  """
  def cooking(%Week{planned_meals: planned_meals}) do
    for planned_meal <- planned_meals,
        %MealRecipe{recipe: recipe} <- planned_meal.meal.meal_recipes,
        not leftover?(planned_meal, recipe.id) do
      taken =
        for leftover <- planned_meal.leftovers_taken,
            leftover.recipe_id == recipe.id,
            do: leftover.planned_meal.servings

      cooked = planned_meal.servings + Enum.sum(taken)

      %{
        planned_meal: planned_meal,
        recipe: recipe,
        cooked_servings: cooked,
        scale: Decimal.div(cooked, recipe.servings)
      }
    end
  end

  @doc "True when `recipe_id` is eaten as leftovers in a planned meal (with leftovers loaded)."
  def leftover?(%PlannedMeal{leftovers: leftovers}, recipe_id),
    do: Enum.any?(leftovers, &(&1.recipe_id == recipe_id))

  ## Planning meals

  @doc """
  Plans a meal in a slot on a date, after any already there, for `servings`
  (default: the household's usual number). Planning in a skipped slot
  removes the skip.
  """
  def plan_meal(
        %Scope{household: household} = scope,
        %Date{} = date,
        slot_id,
        meal_id,
        servings \\ nil
      ) do
    fn ->
      with {:ok, slot} <- fetch_slot(household.id, slot_id),
           {:ok, meal} <- fetch_meal(household.id, meal_id) do
        :ok = delete_skip(household.id, date, slot.id)

        %PlannedMeal{
          household_id: household.id,
          date: date,
          meal_slot_id: slot.id,
          meal_id: meal.id,
          position: next_position(household.id, date, slot.id)
        }
        |> PlannedMeal.servings_changeset(%{servings: servings || household.usually_feeding})
        |> Repo.insert()
      end
    end
    |> Repo.transact()
    |> notify(scope, [date])
  end

  @doc """
  Plans a recipe directly: uses the household's one-recipe meal for it
  (preferring one named after the recipe), creating one named after the
  recipe if there is none.
  """
  def plan_recipe(
        %Scope{household: household} = scope,
        %Date{} = date,
        slot_id,
        recipe_id,
        servings \\ nil
      ) do
    Repo.transact(fn ->
      with {:ok, recipe} <- fetch_recipe(household.id, recipe_id),
           {:ok, meal} <- recipe_meal(scope, recipe) do
        plan_meal(scope, date, slot_id, meal.id, servings)
      end
    end)
  end

  defp recipe_meal(%Scope{household: household} = scope, recipe) do
    existing =
      Repo.one(
        from m in Meal,
          join: mr in assoc(m, :meal_recipes),
          where: m.household_id == ^household.id and is_nil(m.archived_at),
          group_by: m.id,
          having:
            count(mr.id) == 1 and
              fragment("bool_and(? = ?)", mr.recipe_id, type(^recipe.id, :binary_id)),
          order_by: [
            desc: fragment("lower(?) = lower(?)", m.name, ^recipe.name),
            asc: m.inserted_at
          ],
          limit: 1
      )

    if existing do
      {:ok, existing}
    else
      with {:ok, meal} <-
             Meals.create_meal(scope, %{name: free_meal_name(household.id, recipe.name)}) do
        Meals.add_recipe(scope, meal.id, recipe.id)
      end
    end
  end

  # The recipe's name, or "Name (2)", "Name (3)"... if a meal already has it.
  defp free_meal_name(household_id, name) do
    taken =
      from(m in Meal,
        where: m.household_id == ^household_id and is_nil(m.archived_at),
        select: fragment("lower(?)", m.name)
      )
      |> Repo.all()
      |> MapSet.new()

    base = String.slice(name, 0, 110)

    1
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base} (#{n})"
    end)
    |> Enum.find(&(not MapSet.member?(taken, String.downcase(&1))))
  end

  @doc "Changes how many servings a planned meal is for."
  def set_servings(%Scope{} = scope, planned_meal_id, servings) do
    with {:ok, planned_meal} <- fetch_planned_meal(scope, planned_meal_id) do
      planned_meal
      |> PlannedMeal.servings_changeset(%{servings: servings})
      |> Repo.update()
      |> notify(scope, [planned_meal.date])
    end
  end

  @doc """
  Changes which meal is planned. Leftover links for recipes the new meal
  doesn't have are removed.
  """
  def change_meal(%Scope{household: household} = scope, planned_meal_id, meal_id) do
    fn ->
      with {:ok, planned_meal} <- fetch_planned_meal(scope, planned_meal_id),
           {:ok, meal} <- fetch_meal(household.id, meal_id),
           {:ok, planned_meal} <-
             planned_meal |> Ecto.Changeset.change(meal_id: meal.id) |> Repo.update() do
        :ok = prune_leftovers(planned_meal.id)
        {:ok, planned_meal}
      end
    end
    |> Repo.transact()
    |> notify(scope)
  end

  @doc """
  Moves a planned meal to another date and slot, after any meals there.
  Leftover links that are no longer valid (not earlier, or not the same
  week) are removed; moving into a skipped slot removes the skip.
  """
  def move_planned_meal(
        %Scope{household: household} = scope,
        planned_meal_id,
        %Date{} = date,
        slot_id
      ) do
    fn ->
      with {:ok, planned_meal} <- fetch_planned_meal(scope, planned_meal_id),
           {:ok, slot} <- fetch_slot(household.id, slot_id),
           :ok <- delete_skip(household.id, date, slot.id),
           {:ok, moved} <-
             planned_meal
             |> Ecto.Changeset.change(
               date: date,
               meal_slot_id: slot.id,
               position: next_position(household.id, date, slot.id)
             )
             |> Repo.update() do
        :ok = prune_leftovers(moved.id)
        {:ok, {moved, planned_meal.date}}
      end
    end
    |> Repo.transact()
    |> case do
      {:ok, {moved, from}} -> notify({:ok, moved}, scope, [from, moved.date])
      error -> error
    end
  end

  @doc "Removes a planned meal, with any leftover links to or from it."
  def remove_planned_meal(%Scope{} = scope, planned_meal_id) do
    with {:ok, planned_meal} <- fetch_planned_meal(scope, planned_meal_id) do
      planned_meal |> Repo.delete() |> notify(scope)
    end
  end

  ## Skips

  @doc "Marks a slot as needing no meal on a date. Refused while meals are planned there."
  def skip_slot(%Scope{household: household} = scope, %Date{} = date, slot_id) do
    with {:ok, slot} <- fetch_slot(household.id, slot_id),
         :ok <- slot_free(household.id, date, slot.id) do
      %SlotSkip{household_id: household.id, date: date, meal_slot_id: slot.id}
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:meal_slot_id, :date])
      |> case do
        {:ok, _skip} -> notify({:ok, date}, scope, [date])
      end
    end
  end

  @doc "Undoes `skip_slot/3`."
  def unskip_slot(%Scope{household: household} = scope, %Date{} = date, slot_id) do
    with {:ok, slot} <- fetch_slot(household.id, slot_id) do
      :ok = delete_skip(household.id, date, slot.id)
      notify({:ok, date}, scope, [date])
    end
  end

  defp slot_free(household_id, date, slot_id) do
    if Repo.exists?(cell(household_id, date, slot_id)), do: {:error, :has_meals}, else: :ok
  end

  defp delete_skip(household_id, date, slot_id) do
    {_count, _} =
      Repo.delete_all(
        from s in SlotSkip,
          where:
            s.household_id == ^household_id and s.date == ^date and s.meal_slot_id == ^slot_id
      )

    :ok
  end

  ## Leftovers

  @doc """
  Marks `recipe_id` in a planned meal as leftovers of an earlier planned
  meal (see the module docs for the rules).
  """
  def add_leftover(%Scope{household: household} = scope, planned_meal_id, source_id, recipe_id) do
    fn ->
      with {:ok, eater} <- fetch_planned_meal(scope, planned_meal_id),
           {:ok, source} <- fetch_planned_meal(scope, source_id),
           {:ok, recipe_id} <- cast_id(recipe_id),
           [eater, source] = Repo.preload([eater, source], leftover_preloads()),
           :ok <- valid_leftover(eater, source, recipe_id),
           :ok <- fresh_in_source(source, recipe_id),
           :ok <- not_a_source(eater, recipe_id),
           {:ok, leftover} <- insert_leftover(household.id, eater, source, recipe_id) do
        {:ok, {leftover, eater.date}}
      end
    end
    |> Repo.transact()
    |> case do
      {:ok, {leftover, date}} -> notify({:ok, leftover}, scope, [date])
      error -> error
    end
  end

  defp insert_leftover(household_id, eater, source, recipe_id) do
    %Leftover{
      household_id: household_id,
      planned_meal_id: eater.id,
      source_planned_meal_id: source.id,
      recipe_id: recipe_id
    }
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.unique_constraint([:planned_meal_id, :recipe_id])
    |> Repo.insert()
    |> case do
      {:ok, leftover} -> {:ok, leftover}
      {:error, _changeset} -> {:error, :already_leftover}
    end
  end

  @doc "Makes a recipe in a planned meal fresh again."
  def remove_leftover(%Scope{} = scope, planned_meal_id, recipe_id) do
    with {:ok, planned_meal} <- fetch_planned_meal(scope, planned_meal_id),
         {:ok, recipe_id} <- cast_id(recipe_id) do
      {_count, _} =
        Repo.delete_all(
          from l in Leftover,
            where: l.planned_meal_id == ^planned_meal.id and l.recipe_id == ^recipe_id
        )

      notify({:ok, planned_meal}, scope)
    end
  end

  @doc """
  The planned meals a meal on `date` in `slot_id` could take leftovers from:
  earlier ones within `leftover_days/0`, latest first, each with the
  recipes it cooks fresh and what it will cook them for. Repeats of the same
  meal offering the same recipes are listed once, as the latest:

      [%{planned_meal: %PlannedMeal{}, recipes: [%{recipe: %Recipe{}, cooked_servings: 6}]}]

  `except` leaves out a planned meal (the one being edited).
  """
  def leftover_sources(%Scope{household: household}, %Date{} = date, slot_id, except \\ nil) do
    case fetch_slot(household.id, slot_id) do
      {:ok, slot} ->
        since = Date.add(date, -@leftover_days)

        from(pm in PlannedMeal,
          join: s in assoc(pm, :meal_slot),
          where: pm.household_id == ^household.id and pm.date >= ^since and pm.date <= ^date,
          order_by: [desc: pm.date, desc: s.position, desc: pm.position],
          preload: [
            meal_slot: s,
            leftovers: [],
            leftovers_taken: :planned_meal,
            meal: [meal_recipes: :recipe]
          ]
        )
        |> Repo.all()
        |> Enum.filter(&(&1.id != except and earlier?(&1, %{date: date, meal_slot: slot})))
        |> Enum.map(&%{planned_meal: &1, recipes: fresh_recipes(&1)})
        |> Enum.reject(&(&1.recipes == []))
        # Repeats (porridge every morning) collapse to the latest. A copy
        # offering different recipes, because some of them are leftovers
        # there, is kept.
        |> Enum.uniq_by(&{&1.planned_meal.meal_id, Enum.map(&1.recipes, fn r -> r.recipe.id end)})

      _not_found ->
        []
    end
  end

  defp fresh_recipes(planned_meal) do
    for %MealRecipe{recipe: recipe} <- planned_meal.meal.meal_recipes,
        not leftover?(planned_meal, recipe.id) do
      taken =
        for leftover <- planned_meal.leftovers_taken,
            leftover.recipe_id == recipe.id,
            do: leftover.planned_meal.servings

      %{recipe: recipe, cooked_servings: planned_meal.servings + Enum.sum(taken)}
    end
  end

  @doc """
  Plans a meal of leftovers in a slot: `:all` plans the source's meal with
  every recipe it cooks fresh as leftovers; a recipe id plans that recipe
  (as with `plan_recipe/5`) as leftovers. All or nothing.
  """
  def plan_leftovers(%Scope{} = scope, %Date{} = date, slot_id, source_id, which, servings \\ nil) do
    Repo.transact(fn ->
      with {:ok, source} <- fetch_planned_meal(scope, source_id),
           source = Repo.preload(source, [:leftovers, meal: :meal_recipes]),
           {:ok, planned_meal, recipe_ids} <-
             plan_for_leftovers(scope, date, slot_id, source, which, servings),
           :ok <- add_leftovers(scope, planned_meal, source, recipe_ids) do
        {:ok, planned_meal}
      end
    end)
  end

  defp plan_for_leftovers(scope, date, slot_id, source, :all, servings) do
    recipe_ids =
      for mr <- source.meal.meal_recipes, not leftover?(source, mr.recipe_id), do: mr.recipe_id

    with {:ok, planned_meal} <- plan_meal(scope, date, slot_id, source.meal_id, servings) do
      {:ok, planned_meal, recipe_ids}
    end
  end

  defp plan_for_leftovers(scope, date, slot_id, _source, recipe_id, servings) do
    with {:ok, planned_meal} <- plan_recipe(scope, date, slot_id, recipe_id, servings) do
      {:ok, planned_meal, [recipe_id]}
    end
  end

  defp add_leftovers(_scope, _planned_meal, _source, []), do: {:error, :nothing_to_share}

  defp add_leftovers(scope, planned_meal, source, recipe_ids) do
    Enum.reduce_while(recipe_ids, :ok, fn recipe_id, :ok ->
      case add_leftover(scope, planned_meal.id, source.id, recipe_id) do
        {:ok, _leftover} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc "How many leftover links a planned meal has, either way."
  def leftover_links(%Scope{household: %Household{id: household_id}}, planned_meal_id) do
    case cast_id(planned_meal_id) do
      {:ok, id} ->
        Repo.aggregate(
          from(l in Leftover,
            where:
              l.household_id == ^household_id and
                (l.planned_meal_id == ^id or l.source_planned_meal_id == ^id)
          ),
          :count
        )

      {:error, :not_found} ->
        0
    end
  end

  defp leftover_preloads, do: [:meal_slot, :leftovers, :leftovers_taken, meal: :meal_recipes]

  # The rules that must keep holding as meals move or change.
  defp valid_leftover(eater, source, recipe_id) do
    cond do
      Date.diff(eater.date, source.date) > @leftover_days ->
        {:error, :too_far_apart}

      not earlier?(source, eater) ->
        {:error, :not_earlier}

      not has_recipe?(eater, recipe_id) or not has_recipe?(source, recipe_id) ->
        {:error, :recipe_not_in_meal}

      true ->
        :ok
    end
  end

  # Leftovers come from a meal that cooks the recipe, not from leftovers.
  defp fresh_in_source(source, recipe_id) do
    if leftover?(source, recipe_id), do: {:error, :source_is_leftovers}, else: :ok
  end

  # ...and a recipe others take leftovers from must stay cooked fresh.
  defp not_a_source(eater, recipe_id) do
    if Enum.any?(eater.leftovers_taken, &(&1.recipe_id == recipe_id)),
      do: {:error, :is_a_source},
      else: :ok
  end

  defp earlier?(a, b) do
    case Date.compare(a.date, b.date) do
      :lt -> true
      :gt -> false
      :eq -> a.meal_slot.position < b.meal_slot.position
    end
  end

  defp has_recipe?(planned_meal, recipe_id),
    do: Enum.any?(planned_meal.meal.meal_recipes, &(&1.recipe_id == recipe_id))

  # Removes this planned meal's leftover links, either way, that no longer
  # satisfy the rules.
  defp prune_leftovers(planned_meal_id) do
    invalid =
      from(l in Leftover,
        where:
          l.planned_meal_id == ^planned_meal_id or l.source_planned_meal_id == ^planned_meal_id,
        preload: [planned_meal: ^leftover_preloads(), source_planned_meal: ^leftover_preloads()]
      )
      |> Repo.all()
      |> Enum.reject(
        &(valid_leftover(&1.planned_meal, &1.source_planned_meal, &1.recipe_id) == :ok)
      )
      |> Enum.map(& &1.id)

    {_count, _} = Repo.delete_all(from l in Leftover, where: l.id in ^invalid)
    :ok
  end

  ## Lookups

  defp fetch_planned_meal(%Scope{household: %Household{id: household_id}}, id) do
    with {:ok, id} <- cast_id(id),
         %PlannedMeal{} = planned_meal <-
           Repo.get_by(PlannedMeal, id: id, household_id: household_id) do
      {:ok, planned_meal}
    else
      _ -> {:error, :not_found}
    end
  end

  defp fetch_slot(household_id, id), do: fetch_active(MealSlot, household_id, id)
  defp fetch_meal(household_id, id), do: fetch_active(Meal, household_id, id)
  defp fetch_recipe(household_id, id), do: fetch_active(Recipe, household_id, id)

  defp fetch_active(schema, household_id, id) do
    with {:ok, id} <- cast_id(id),
         %{} = found <-
           Repo.one(
             from x in schema,
               where: x.id == ^id and x.household_id == ^household_id and is_nil(x.archived_at)
           ) do
      {:ok, found}
    else
      _ -> {:error, :not_found}
    end
  end

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp cell(household_id, date, slot_id) do
    from pm in PlannedMeal,
      where: pm.household_id == ^household_id and pm.date == ^date and pm.meal_slot_id == ^slot_id
  end

  defp next_position(household_id, date, slot_id) do
    last = Repo.one(from pm in cell(household_id, date, slot_id), select: max(pm.position))
    (last || -1) + 1
  end

  defp notify(result, scope, dates \\ nil)

  defp notify({:ok, value} = result, scope, dates) do
    dates = dates || [value.date]

    for week <- dates |> Enum.map(&week_start/1) |> Enum.uniq() do
      :ok = Households.broadcast(scope, {:plan_changed, week})
    end

    result
  end

  defp notify(error, _scope, _dates), do: error
end
