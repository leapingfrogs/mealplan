defmodule Mealplan.Shopping do
  @moduledoc """
  The shopping list (iteration 4 design). What to buy is computed from the
  plan whenever it's needed, so it always matches the plan.
  """
  import Ecto.Query

  alias Mealplan.Accounts.Scope
  alias Mealplan.Households
  alias Mealplan.Households.Household
  alias Mealplan.Planning
  alias Mealplan.Recipes.RecipeIngredient
  alias Mealplan.Repo
  alias Mealplan.Shopping.Item
  alias Mealplan.Shopping.Line
  alias Mealplan.Shopping.Quantity
  alias Mealplan.Shopping.ShoppingList
  alias Mealplan.Shopping.Staple
  alias Mealplan.Shopping.Tick
  alias Mealplan.Shopping.View

  ## The list

  @doc """
  The household's shopping list, created on first use for the default
  range: today to the end of the week the planner opens on.
  """
  def get_list(%Scope{household: %Household{id: household_id}} = scope) do
    case Repo.get_by(ShoppingList, household_id: household_id) do
      %ShoppingList{} = list ->
        list

      nil ->
        {starts_on, ends_on} = default_range(scope)

        Repo.insert!(
          %ShoppingList{household_id: household_id, starts_on: starts_on, ends_on: ends_on},
          on_conflict: :nothing,
          conflict_target: :household_id
        )

        Repo.get_by!(ShoppingList, household_id: household_id)
    end
  end

  @doc "Today to the end of the week the planner opens on."
  def default_range(%Scope{} = scope) do
    {Planning.today(scope), Date.add(Planning.default_week(scope), 6)}
  end

  @doc "A changeset for the list's range, for forms."
  def change_range(%ShoppingList{} = list, attrs \\ %{}),
    do: ShoppingList.range_changeset(list, attrs)

  @doc """
  Sets the list's range (at most `ShoppingList.max_days/0` days). Ticks and
  manual items are kept.
  """
  def set_range(%Scope{} = scope, attrs) do
    scope
    |> get_list()
    |> ShoppingList.range_changeset(attrs)
    |> Repo.update()
    |> notify(scope)
  end

  @doc """
  The list as shown (`Mealplan.Shopping.View`): what's needed for its range
  split into lines to buy, lines ticked and staples, plus manual items. Ticks
  for lines no longer needed (the range or the plan changed) are kept, hidden,
  until a new list is started, so a line that comes back is still ticked.
  """
  def view(%Scope{} = scope) do
    list = Repo.preload(get_list(scope), [:ticks, :items])
    staple_keys = scope |> list_staples() |> MapSet.new(& &1.key)

    {staples, lines} =
      scope
      |> needs(list.starts_on, list.ends_on)
      |> Enum.split_with(&MapSet.member?(staple_keys, &1.key))

    ticks = Map.new(list.ticks, &{&1.key, &1})
    entries = Enum.map(lines, &entry(&1, Map.get(ticks, &1.key)))

    %View{
      list: list,
      to_buy: entries |> Enum.reject(& &1.ticked) |> Enum.map(&Map.delete(&1, :ticked)),
      ticked: entries |> Enum.filter(& &1.ticked) |> Enum.map(&Map.delete(&1, :ticked)),
      staples: staples,
      items: list.items
    }
  end

  # A line with no tick is to buy; one ticked stays ticked unless more is now
  # needed than when it was ticked.
  defp entry(line, nil), do: %{line: line, more: nil, ticked: false}

  defp entry(line, %Tick{quantity: quantity}) do
    case Quantity.more(line.quantity, Quantity.from_map(quantity)) do
      nil -> %{line: line, more: nil, ticked: true}
      more -> %{line: line, more: more, ticked: false}
    end
  end

  @doc "Ticks the line for `key` at the quantity it needs now."
  def tick(%Scope{} = scope, key) when is_binary(key) do
    list = get_list(scope)

    case Enum.find(needs(scope, list.starts_on, list.ends_on), &(&1.key == key)) do
      %Line{} = line ->
        %Tick{
          household_id: list.household_id,
          shopping_list_id: list.id,
          key: key,
          quantity: Quantity.to_map(line.quantity),
          amount: String.slice(line.amount, 0, 255)
        }
        |> Repo.insert(
          on_conflict: {:replace, [:quantity, :amount, :updated_at]},
          conflict_target: [:shopping_list_id, :key]
        )
        |> notify(scope)

      nil ->
        {:error, :not_found}
    end
  end

  @doc "Unticks the line for `key`."
  def untick(%Scope{} = scope, key) when is_binary(key) do
    list = get_list(scope)

    {_count, _rows} =
      Repo.delete_all(from t in Tick, where: t.shopping_list_id == ^list.id and t.key == ^key)

    notify({:ok, list}, scope)
  end

  @doc """
  Starts a new list: forgets every tick and the manual items already
  bought, keeps the rest, and resets the range to the default.
  """
  def start_new(%Scope{} = scope) do
    list = get_list(scope)
    {starts_on, ends_on} = default_range(scope)

    fn ->
      {_count, _rows} = Repo.delete_all(from t in Tick, where: t.shopping_list_id == ^list.id)

      {_count, _rows} =
        Repo.delete_all(
          from i in Item, where: i.shopping_list_id == ^list.id and not is_nil(i.ticked_at)
        )

      list
      |> Ecto.Changeset.change(starts_on: starts_on, ends_on: ends_on)
      |> Repo.update()
    end
    |> Repo.transact()
    |> notify(scope)
  end

  ## Manual items

  @doc "A changeset for a manual item, for forms."
  def change_item(%Item{} = item \\ %Item{}, attrs \\ %{}), do: Item.changeset(item, attrs)

  @doc "Adds an item by hand, after the others."
  def add_item(%Scope{} = scope, attrs) do
    list = get_list(scope)

    last =
      Repo.one(from i in Item, where: i.shopping_list_id == ^list.id, select: max(i.position))

    %Item{household_id: list.household_id, shopping_list_id: list.id, position: (last || 0) + 1}
    |> Item.changeset(attrs)
    |> Repo.insert()
    |> notify(scope)
  end

  @doc "Ticks or unticks a manual item."
  def tick_item(%Scope{} = scope, item_id, ticked?) when is_boolean(ticked?) do
    with {:ok, item} <- fetch_item(scope, item_id) do
      ticked_at = if ticked?, do: DateTime.utc_now(:second)

      item
      |> Ecto.Changeset.change(ticked_at: ticked_at)
      |> Repo.update()
      |> notify(scope)
    end
  end

  @doc "Removes a manual item."
  def remove_item(%Scope{} = scope, item_id) do
    with {:ok, item} <- fetch_item(scope, item_id) do
      item |> Repo.delete() |> notify(scope)
    end
  end

  defp fetch_item(%Scope{} = scope, item_id) do
    list = get_list(scope)

    with {:ok, id} <- Ecto.UUID.cast(item_id),
         %Item{} = item <- Repo.get_by(Item, id: id, shopping_list_id: list.id) do
      {:ok, item}
    else
      _missing -> {:error, :not_found}
    end
  end

  ## Staples

  @doc "The household's staples, by name."
  def list_staples(%Scope{household: %Household{id: household_id}}) do
    Repo.all(from s in Staple, where: s.household_id == ^household_id, order_by: s.name)
  end

  @doc "A changeset for a staple, for forms."
  def change_staple(%Staple{} = staple \\ %Staple{}, attrs \\ %{}),
    do: Staple.changeset(staple, attrs)

  @doc """
  Makes an ingredient a staple (by name; it matches lines by key), so it's
  left off the list.
  """
  def add_staple(%Scope{household: %Household{id: household_id}} = scope, attrs) do
    %Staple{household_id: household_id}
    |> Staple.changeset(attrs)
    |> Repo.insert()
    |> notify(scope)
  end

  @doc "Stops an ingredient being a staple."
  def remove_staple(%Scope{household: %Household{id: household_id}} = scope, staple_id) do
    with {:ok, id} <- Ecto.UUID.cast(staple_id),
         %Staple{} = staple <- Repo.get_by(Staple, id: id, household_id: household_id) do
      staple |> Repo.delete() |> notify(scope)
    else
      _missing -> {:error, :not_found}
    end
  end

  defp notify({:ok, _changed} = result, %Scope{household: %Household{id: household_id}} = scope) do
    :ok = Households.broadcast(scope, {:shopping_changed, household_id})
    result
  end

  defp notify(error, _scope), do: error

  ## What's needed

  @doc """
  What's needed for the meals planned from `first` to `last` (inclusive):
  each recipe cooked fresh, scaled to its cooked servings (leftovers count in
  the meal they're taken from; eating them adds nothing), its ingredients
  merged by key across recipes. Lines are in name order.
  """
  def needs(
        %Scope{household: %Household{id: household_id}} = scope,
        %Date{} = first,
        %Date{} = last
      ) do
    cooking = Planning.cooking(scope, first, last)

    rows =
      from(i in RecipeIngredient,
        where:
          i.household_id == ^household_id and
            i.recipe_id in ^Enum.map(cooking, & &1.recipe.id),
        order_by: [i.recipe_id, i.position]
      )
      |> Repo.all()
      |> Enum.group_by(& &1.recipe_id)

    cooking
    |> Enum.flat_map(&sources(&1, Map.get(rows, &1.recipe.id, [])))
    |> Enum.group_by(fn {key, _name, _optional, _source} -> key end)
    |> Enum.map(fn {key, [{_key, name, _optional, _source} | _rest] = parts} ->
      quantity = parts |> Enum.map(&elem(&1, 3).quantity) |> Quantity.sum()

      %Line{
        key: key,
        name: name,
        quantity: quantity,
        amount: Quantity.to_string(quantity),
        optional: Enum.all?(parts, &elem(&1, 2)),
        sources: Enum.map(parts, &elem(&1, 3))
      }
    end)
    |> Enum.sort_by(&{String.downcase(&1.name), &1.key})
  end

  # One source per ingredient key in a cooked recipe: its rows scaled and
  # added up, with the first row's name.
  defp sources(cooked, rows) do
    rows
    |> Enum.group_by(& &1.key)
    |> Enum.map(fn {key, [first | _rest] = rows} ->
      quantity = rows |> Enum.map(&Quantity.new(&1, cooked.scale)) |> Quantity.sum()

      source = %{
        planned_meal: cooked.planned_meal,
        recipe: cooked.recipe,
        quantity: quantity,
        amount: Quantity.to_string(quantity)
      }

      {key, first.name, Enum.all?(rows, & &1.optional), source}
    end)
  end
end
