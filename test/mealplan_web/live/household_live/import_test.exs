defmodule MealplanWeb.HouseholdLive.ImportTest do
  use MealplanWeb.ConnCase, async: true

  import Mealplan.HouseholdsFixtures
  import Mealplan.MealsFixtures
  import Mealplan.RecipesFixtures
  import Phoenix.LiveViewTest

  alias Mealplan.Meals
  alias Mealplan.Recipes
  alias Mealplan.Repo
  alias Mealplan.Transfer

  setup :register_and_log_in_user_with_household

  defp upload(view, files) do
    input =
      file_input(
        view,
        "#upload-form",
        :files,
        Enum.map(files, fn {name, content} -> %{name: name, content: content} end)
      )

    for {name, _content} <- files, do: render_upload(input, name)
    view |> form("#upload-form") |> render_submit()
  end

  defp exported_zip do
    %{scope: other} = household_fixture()
    chilli = recipe_fixture(other, %{name: "Chilli", servings: 6, source: "Cook @beans{400%g}."})
    salad = recipe_fixture(other, %{name: "Salad", servings: 2})
    meal_fixture(other, %{name: "Chilli night"}, [chilli, salad])
    {:ok, {name, zip}} = Transfer.export(other)
    {name, zip}
  end

  test "imports another household's export, with choices", %{conn: conn, scope: scope} do
    ours = recipe_fixture(scope, %{name: "Chilli", servings: 4, source: "Ours."})
    {:ok, view, _html} = live(conn, ~p"/household/import")

    html = upload(view, [exported_zip()])

    assert html =~ "2 recipes and 1 meal: 2 new, 1 already here."
    assert has_element?(view, "#item-recipe-0", "we already have Chilli")
    assert has_element?(view, "#item-recipe-0 option[selected][value=skip]")
    assert has_element?(view, "#item-meal-0", "Chilli (ours), Salad")

    view |> form("#import-choices", choices: %{"recipe-0" => "replace"}) |> render_change()
    assert has_element?(view, "#item-meal-0", "Chilli, Salad")

    view |> form("#import-choices", choices: %{"recipe-1" => "leave_out"}) |> render_change()
    assert has_element?(view, "#item-meal-0", "Salad (left out)")
    view |> form("#import-choices", choices: %{"recipe-1" => "add"}) |> render_change()

    html = view |> form("#import-choices") |> render_submit()

    assert html =~ "Imported."
    assert has_element?(view, "#import-summary", "Recipes: 1 added, 1 replaced")
    assert has_element?(view, "#import-summary", "Meals: 1 added")
    assert Repo.reload!(ours).servings == 6
    assert ["Chilli night"] = scope |> Meals.list_meals() |> Enum.map(& &1.name)

    view |> element("#import-summary button", "Import more") |> render_click()
    assert has_element?(view, "#upload-form")
  end

  test "loose .cook and .menu files, problems and parse warnings", %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/household/import")

    upload(view, [
      {"pancakes.cook", "---\ntitle: Pancakes\n---\nMix @flour{100%g}. [- unfinished"},
      {"week.menu", "= Brunch\n@./pancakes{} @Toast{}"},
      {"broken.cook", <<0xFF>>}
    ])

    assert has_element?(view, "#item-recipe-0", "Serves #{scope.household.usually_feeding}")
    assert has_element?(view, "#item-recipe-0 details", "1 problem in the recipe")
    assert has_element?(view, "#item-meal-0", "Pancakes, Toast (not found)")
    assert has_element?(view, "#import-problems", "broken.cook")

    view |> form("#import-choices") |> render_submit()
    assert [%{name: "Pancakes"}] = Recipes.list_recipes(scope)
  end

  test "nothing to import, and starting over", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/household/import")
    upload(view, [{"notes.zip", "not a zip"}])

    assert render(view) =~ "Nothing to import in those files."
    refute has_element?(view, "#apply-import")
    assert has_element?(view, "#import-problems", "isn't a zip file we can read")

    view |> element("#cancel-import") |> render_click()
    assert has_element?(view, "#upload-form")
  end

  test "refuses files of the wrong type before uploading", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/household/import")
    input = file_input(view, "#upload-form", :files, [%{name: "photo.jpg", content: "x"}])

    assert {:error, [[_ref, :not_accepted]]} = render_upload(input, "photo.jpg")
  end

  test "a file can be removed before continuing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/household/import")
    input = file_input(view, "#upload-form", :files, [%{name: "a.cook", content: "@salt"}])
    render_upload(input, "a.cook")
    assert has_element?(view, "#chosen-files", "a.cook")

    view |> element("#chosen-files button") |> render_click()
    refute has_element?(view, "#chosen-files")
  end

  test "tells the owner when nothing was imported", %{conn: conn, scope: scope} do
    rice = recipe_fixture(scope, %{name: "Rice"})
    {:ok, view, _html} = live(conn, ~p"/household/import")
    upload(view, [{"a.menu", "= Rice bowl\n@Rice{}"}])

    # Rice goes away between the preview and the import.
    rice |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second)) |> Repo.update!()

    assert view |> form("#import-choices") |> render_submit() =~ "Nothing was imported"
    assert Meals.list_meals(scope) == []
  end

  test "is rate limited", %{conn: conn, scope: scope} do
    for _ <- 1..5, do: {:ok, _} = Transfer.apply(scope, %Transfer.Import{}, %{})
    {:ok, view, _html} = live(conn, ~p"/household/import")
    upload(view, [{"a.cook", "@salt"}])

    assert view |> form("#import-choices") |> render_submit() =~ "try again in an hour"
  end

  test "is for the owner only; the household page links it", %{conn: conn, scope: scope} do
    {:ok, settings, _html} = live(conn, ~p"/household")
    assert has_element?(settings, "#import-household[href='/household/import']")

    %{user: member} = member_fixture(scope.household)
    member_conn = log_in_user(build_conn(), member)

    assert {:error,
            {:live_redirect, %{to: "/household", flash: %{"error" => "Only the household" <> _}}}} =
             live(member_conn, ~p"/household/import")
  end

  describe "slot tags" do
    setup %{conn: conn, scope: scope} do
      slots = scope |> Mealplan.Households.list_meal_slots() |> Map.new(&{&1.name, &1.id})

      menu = """
      = Chilli night

      > Slots: Dinner, Brunch

      = Picnic

      = Eat out

      = Toast
      """

      {:ok, view, _html} = live(conn, ~p"/household/import")
      upload(view, [{"week.menu", menu}])
      %{view: view, slots: slots}
    end

    defp chip(key, slot_id), do: "#slot-#{key}-#{slot_id}"

    defp pressed?(view, key, slot_id),
      do: has_element?(view, chip(key, slot_id) <> "[aria-pressed=true]")

    defp meal_slots(scope, name) do
      meal = Enum.find(Meals.list_meals(scope), &(&1.name == name))
      Enum.map(meal.slots, & &1.name)
    end

    test "matched tags are chosen, unmatched names shown, and chips toggle", %{view: view} = c do
      assert pressed?(view, "meal-0", c.slots["Dinner"])
      refute pressed?(view, "meal-0", c.slots["Lunch"])
      assert has_element?(view, "#unmatched-meal-0", "Brunch: no such slot")
      refute has_element?(view, "#unmatched-meal-1")

      view |> element(chip("meal-1", c.slots["Lunch"])) |> render_click()
      assert pressed?(view, "meal-1", c.slots["Lunch"])
      view |> element(chip("meal-0", c.slots["Dinner"])) |> render_click()
      refute pressed?(view, "meal-0", c.slots["Dinner"])

      # Left out, its tags don't matter.
      view |> form("#import-choices", choices: %{"meal-3" => "leave_out"}) |> render_change()
      refute has_element?(view, "#slots-meal-3")
    end

    test "sets slots for meals without any, then imports them", %{view: view, scope: scope} = c do
      view |> element(chip("meal-1", c.slots["Lunch"])) |> render_click()
      assert has_element?(view, "#bulk-slots", "(2 meals)")
      assert has_element?(view, "#apply-bulk-slots[disabled]")

      view |> element(chip("bulk", c.slots["Dinner"])) |> render_click()
      view |> element(chip("bulk", c.slots["Snack"])) |> render_click()
      view |> element(chip("bulk", c.slots["Snack"])) |> render_click()
      view |> element("#apply-bulk-slots") |> render_click()

      refute has_element?(view, "#bulk-slots")
      assert pressed?(view, "meal-2", c.slots["Dinner"])
      refute pressed?(view, "meal-1", c.slots["Dinner"])

      view |> form("#import-choices") |> render_submit()
      assert meal_slots(scope, "Chilli night") == ["Dinner"]
      assert meal_slots(scope, "Picnic") == ["Lunch"]
      assert meal_slots(scope, "Eat out") == ["Dinner"]
      assert meal_slots(scope, "Toast") == ["Dinner"]
    end

    test "ignores slots that aren't ours", %{view: view} do
      render_click(view, "toggle_slot", %{"key" => "meal-1", "slot" => Ecto.UUID.generate()})
      render_click(view, "toggle_bulk_slot", %{"slot" => "nope"})
      render_click(view, "toggle_slot", %{"key" => "meal-9", "slot" => "nope"})
      assert has_element?(view, "#apply-bulk-slots[disabled]")
    end
  end
end
