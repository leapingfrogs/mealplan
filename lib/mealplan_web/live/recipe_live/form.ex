defmodule MealplanWeb.RecipeLive.Form do
  @moduledoc """
  Creates and edits recipes. The Cooklang source is parsed as you type
  (debounced) for the ingredient summary, warnings and the Preview tab;
  warnings never stop a recipe being saved.
  """
  use MealplanWeb, :live_view

  import MealplanWeb.RecipeComponents

  alias Mealplan.Cooklang
  alias Mealplan.Recipes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} section="recipes">
      <.link navigate={@back} class="text-sm text-base-content/60 hover:text-base-content">
        <.icon name="hero-arrow-left" class="size-4" /> {if @live_action == :new,
          do: "Recipes",
          else: @recipe.name}
      </.link>

      <.header>{@page_title}</.header>

      <div :if={@changed_elsewhere?} id="changed-elsewhere" role="alert" class="alert alert-warning">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>Someone else just saved this recipe. Saving now will replace their changes.</span>
      </div>

      <.form for={@form} id="recipe-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <div class="grid grid-cols-[1fr_6rem] gap-3">
          <.input field={@form[:name]} label="Name" autocomplete="off" phx-debounce="300" />
          <.input
            field={@form[:servings]}
            type="number"
            label="Serves"
            min="1"
            max="100"
            inputmode="numeric"
          />
        </div>

        <div role="tablist" class="tabs tabs-border">
          <button
            :for={{tab, label} <- [{"write", "Write"}, {"preview", "Preview"}]}
            type="button"
            role="tab"
            id={"tab-#{tab}"}
            class={["tab", @tab == tab && "tab-active"]}
            aria-selected={to_string(@tab == tab)}
            phx-click="tab"
            phx-value-tab={tab}
          >
            {label}
          </button>
        </div>

        <div id="write-panel" class={["space-y-3", @tab != "write" && "hidden"]}>
          <.input
            field={@form[:source]}
            type="textarea"
            rows="14"
            spellcheck="false"
            phx-debounce="300"
            aria-label="Recipe in Cooklang"
            placeholder="Whisk @eggs{3} with @milk{300%ml} in a #bowl{}. Rest for ~{30%minutes}."
            class="textarea w-full font-mono text-sm leading-relaxed"
          />
          <p class="text-xs text-base-content/60">
            Each paragraph is a step. Mark ingredients <code>@flour{"{250%g}"}</code>, cookware
            <code>#pan{"{}"}</code>
            and timers <code>~{"{10%minutes}"}</code>.
            <a
              href="https://cooklang.org/docs/spec/"
              target="_blank"
              rel="noopener noreferrer"
              class="link"
            >
              Cooklang guide
            </a>
          </p>
          <.warnings id="source-warnings" warnings={@parsed.warnings} />
          <div :if={@parsed.ingredients != []} id="ingredient-summary" class="flex flex-wrap gap-1.5">
            <span
              :for={ingredient <- @parsed.ingredients}
              class="badge badge-soft badge-primary gap-1"
            >
              {ingredient.name}
              <span :if={amount(ingredient.quantity, ingredient.unit)} class="opacity-70">
                {amount(ingredient.quantity, ingredient.unit)}
              </span>
            </span>
          </div>
        </div>

        <div id="preview-panel" class={["space-y-6", @tab != "preview" && "hidden"]}>
          <p
            :if={@parsed.ingredients == [] and @parsed.sections |> Enum.all?(&(&1.blocks == []))}
            class="py-6 text-center text-base-content/60"
          >
            Nothing to preview yet.
          </p>
          <section :if={@parsed.ingredients != []} class="space-y-2">
            <h2 class="font-semibold">Ingredients</h2>
            <.ingredient_list id="preview-ingredients" ingredients={@parsed.ingredients} />
          </section>
          <.method id="preview-method" recipe={@parsed} />
        </div>

        <div class="flex gap-2 pt-2">
          <.button variant="primary" phx-disable-with="Saving..." id="save-recipe">
            Save recipe
          </.button>
          <.button navigate={@back}>Cancel</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(tab: "write", changed_elsewhere?: false)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    recipe = Recipes.new_recipe(socket.assigns.current_scope)

    socket
    |> assign(page_title: "New recipe", recipe: recipe, back: ~p"/recipes")
    |> assign_form(Recipes.change_recipe(recipe))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    recipe = Recipes.get_recipe!(socket.assigns.current_scope, id)

    socket
    |> assign(page_title: "Edit recipe", recipe: recipe, back: ~p"/recipes/#{recipe}")
    |> assign_form(Recipes.change_recipe(recipe))
  end

  @impl true
  def handle_event("validate", %{"recipe" => params}, socket) do
    changeset = Recipes.change_recipe(socket.assigns.recipe, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("tab", %{"tab" => tab}, socket) when tab in ~w(write preview) do
    {:noreply, assign(socket, tab: tab)}
  end

  def handle_event("save", %{"recipe" => params}, socket) do
    case save(socket, socket.assigns.live_action, params) do
      {:ok, recipe} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{recipe.name} saved.")
         |> push_navigate(to: ~p"/recipes/#{recipe}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(tab: "write") |> assign_form(changeset)}
    end
  end

  defp save(socket, :new, params), do: Recipes.create_recipe(socket.assigns.current_scope, params)

  defp save(socket, :edit, params),
    do: Recipes.update_recipe(socket.assigns.current_scope, socket.assigns.recipe, params)

  # Another member saved the recipe being edited here.
  @impl true
  def handle_info({:recipe_changed, id}, %{assigns: %{recipe: %{id: id}}} = socket) do
    {:noreply, assign(socket, changed_elsewhere?: true)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp assign_form(socket, changeset) do
    source = Ecto.Changeset.get_field(changeset, :source)
    assign(socket, form: to_form(changeset), parsed: Cooklang.parse(source))
  end
end
