defmodule MealplanWeb.ExportController do
  @moduledoc """
  Downloads of a household's recipes and meals (ADR 14). Owner only;
  anyone else gets a 404, so the routes aren't advertised.
  """
  use MealplanWeb, :controller

  alias Mealplan.Recipes
  alias Mealplan.Transfer

  def household(conn, _params) do
    conn.assigns.current_scope
    |> Transfer.export()
    |> send_file_or_404(conn, "application/zip")
  end

  def recipe(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope

    case scope.household && Recipes.get_recipe(scope, id) do
      %Recipes.Recipe{} = recipe ->
        scope |> Transfer.recipe_file(recipe) |> send_file_or_404(conn, "text/plain")

      _not_found ->
        not_found(conn)
    end
  end

  defp send_file_or_404({:ok, {file_name, content}}, conn, content_type) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> send_download({:binary, content}, filename: file_name, content_type: content_type)
  end

  defp send_file_or_404({:error, _reason}, conn, _content_type), do: not_found(conn)

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_root_layout(false)
    |> put_view(html: MealplanWeb.ErrorHTML)
    |> render(:"404")
  end
end
