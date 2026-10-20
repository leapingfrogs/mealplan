defmodule Mealplan.Shopping do
  @moduledoc """
  The shopping list (iteration 4 design). What to buy is computed from the
  plan whenever it's needed, so it always matches the plan.
  """
  import Ecto.Query

  alias Mealplan.Accounts.Scope
  alias Mealplan.Households.Household
  alias Mealplan.Planning
  alias Mealplan.Recipes.RecipeIngredient
  alias Mealplan.Repo
  alias Mealplan.Shopping.Line
  alias Mealplan.Shopping.Quantity

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
