defmodule MealplanWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias MealplanWeb.CoreComponents

  defp classes(assigns) do
    ~H"""
    <CoreComponents.button {@attrs}>Save</CoreComponents.button>
    """
    |> rendered_to_string()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("button")
    |> LazyHTML.attribute("class")
    |> hd()
    |> String.split()
  end

  describe "button/1" do
    test "a page's classes add to the variant's instead of replacing them" do
      assert classes(%{attrs: %{variant: "primary", class: "mt-4 w-full"}}) ==
               ~w(btn btn-primary mt-4 w-full)

      assert classes(%{attrs: %{class: "mt-2"}}) == ~w(btn btn-primary btn-soft mt-2)
      assert classes(%{attrs: %{variant: "danger"}}) == ~w(btn btn-error)
      assert classes(%{attrs: %{variant: "neutral"}}) == ~w(btn)
    end
  end
end
