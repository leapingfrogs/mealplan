defmodule MealplanWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MealplanWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders the app shell around a page.

  With a household: a top bar and a bottom tab bar on phones, a sidebar from
  1024 px. Signed in without a household (onboarding, account): the top bar
  only. Signed out: the logo and theme toggle. `section` marks the current
  section in the navigation.

  ## Examples

      <Layouts.app flash={@flash} current_scope={@current_scope} section="recipes">
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :section, :string,
    default: nil,
    values: [nil | ~w(plan recipes meals shopping household account)],
    doc: "the section this page belongs to, marked in the navigation"

  attr :wide, :boolean, default: false, doc: "use the wide width on large screens (the week grid)"

  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assign(assigns,
        household?: assigns.current_scope != nil and assigns.current_scope.household != nil,
        sections: sections()
      )

    ~H"""
    <div class={["min-h-dvh", @household? && "lg:flex"]}>
      <aside
        :if={@household?}
        id="sidebar"
        class="sticky top-0 hidden h-dvh w-64 shrink-0 flex-col gap-6 overflow-y-auto border-r border-base-300 bg-base-100 px-3 py-5 lg:flex"
      >
        <div class="space-y-1 px-2">
          <.brand href={~p"/plan"} />
          <p id="household-name" class="text-sm text-base-content/70 break-words">
            {@current_scope.household.name}
          </p>
        </div>
        <nav aria-label="Sections" class="flex flex-col gap-0.5">
          <.link
            :for={item <- @sections}
            navigate={item.path}
            id={"nav-#{item.id}"}
            aria-current={item.id == @section && "page"}
            class={[
              "flex min-h-11 items-center gap-3 rounded-field px-3 font-medium transition-colors",
              if(item.id == @section,
                do: "bg-primary/10 text-primary",
                else: "text-base-content/80 hover:bg-base-200 hover:text-base-content"
              )
            ]}
          >
            <.section_icon id={item.id} active={item.id == @section} class="size-5" />
            {item.label}
          </.link>
        </nav>
        <div class="mt-auto border-t border-base-300 px-2 pt-4">
          <.account_menu current_scope={@current_scope} section={@section} />
        </div>
      </aside>

      <div class="flex min-w-0 flex-1 flex-col">
        <header
          id="top-bar"
          class={[
            "sticky top-0 z-30 flex min-h-14 items-center justify-between gap-3 border-b border-base-300 bg-base-100/95 px-4 pt-[env(safe-area-inset-top)] backdrop-blur",
            @household? && "lg:hidden"
          ]}
        >
          <.brand href={if(@household?, do: ~p"/plan", else: ~p"/")} />
          <%= if @current_scope do %>
            <details id="account-dropdown" class="dropdown dropdown-end">
              <summary
                class="btn btn-ghost btn-circle list-none"
                aria-label="Account, theme and log out"
              >
                <.avatar email={@current_scope.user.email} />
              </summary>
              <div class="dropdown-content z-40 mt-2 w-72 rounded-box border border-base-300 bg-base-100 p-4 shadow-lg">
                <.account_menu current_scope={@current_scope} section={@section} />
              </div>
            </details>
          <% else %>
            <.theme_toggle />
          <% end %>
        </header>

        <main class={[
          "flex-1 px-4 pt-6 sm:px-6 lg:px-10 lg:py-10",
          if(@household?, do: "pb-[calc(var(--tab-bar)+2.5rem)] lg:pb-10", else: "pb-10")
        ]}>
          <div class={[
            "mx-auto space-y-4",
            if(@wide, do: "max-w-content lg:max-w-wide", else: "max-w-content")
          ]}>
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    </div>

    <nav
      :if={@household?}
      id="tab-bar"
      aria-label="Sections"
      class="fixed inset-x-0 bottom-0 z-30 grid h-(--tab-bar) grid-cols-5 border-t border-base-300 bg-base-100/95 px-1 pb-[env(safe-area-inset-bottom)] backdrop-blur lg:hidden"
    >
      <.link
        :for={item <- @sections}
        navigate={item.path}
        id={"tab-#{item.id}"}
        aria-current={item.id == @section && "page"}
        class={[
          "flex flex-col items-center justify-center gap-0.5 text-xs",
          if(item.id == @section,
            do: "font-semibold text-primary",
            else: "font-medium text-base-content/70"
          )
        ]}
      >
        <span class={[
          "flex h-7 w-12 items-center justify-center rounded-full transition-colors",
          item.id == @section && "bg-primary/10"
        ]}>
          <.section_icon id={item.id} active={item.id == @section} class="size-5" />
        </span>
        {item.label}
      </.link>
    </nav>

    <.flash_group flash={@flash} />
    """
  end

  defp sections do
    [
      %{id: "plan", label: "Plan", path: ~p"/plan"},
      %{id: "recipes", label: "Recipes", path: ~p"/recipes"},
      %{id: "meals", label: "Meals", path: ~p"/meals"},
      %{id: "shopping", label: "Shopping", path: ~p"/shopping"},
      %{id: "household", label: "Household", path: ~p"/household"}
    ]
  end

  attr :href, :string, required: true

  defp brand(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class="inline-flex items-center gap-2 font-display text-xl font-bold tracking-tight"
    >
      <svg viewBox="0 0 24 24" class="size-6 text-primary" fill="none" aria-hidden="true">
        <path d="M3.5 11.5h17a8.5 8.5 0 0 1-17 0z" fill="currentColor" />
        <path
          d="M9.5 9c0-1.9 1.9-2.2 1.9-4.3M13.3 9c0-1.9 1.9-2.2 1.9-4.3"
          stroke="currentColor"
          stroke-width="1.6"
          stroke-linecap="round"
        />
      </svg>
      Mealplan
    </.link>
    """
  end

  attr :email, :string, required: true

  defp avatar(assigns) do
    ~H"""
    <span class="flex size-8 items-center justify-center rounded-full bg-neutral text-sm font-semibold uppercase text-neutral-content">
      {String.first(@email)}
    </span>
    """
  end

  attr :current_scope, :map, required: true
  attr :section, :string, default: nil

  # Who's signed in, the theme, the account page and log out: the sidebar's
  # footer on wide screens, the top bar's menu on phones.
  defp account_menu(assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="flex min-w-0 items-center gap-2.5">
        <.avatar email={@current_scope.user.email} />
        <span class="min-w-0 truncate text-sm" title={@current_scope.user.email}>
          {@current_scope.user.email}
        </span>
      </div>
      <.theme_toggle />
      <div class="flex items-center justify-between gap-2 text-sm">
        <.link
          navigate={~p"/users/settings"}
          aria-current={@section == "account" && "page"}
          class={[
            "inline-flex min-h-10 items-center hover:underline",
            @section == "account" && "font-semibold text-primary"
          ]}
        >
          Account
        </.link>
        <.link
          href={~p"/users/log-out"}
          method="delete"
          class="inline-flex min-h-10 items-center hover:underline"
        >
          Log out
        </.link>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :active, :boolean, default: false
  attr :class, :any, default: nil

  # Meals has no hero icon; it shares the bowl from the logo.
  defp section_icon(%{id: "meals"} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" class={@class} fill="none" aria-hidden="true">
      <path
        d="M3.5 11.5h17a8.5 8.5 0 0 1-17 0z"
        fill={if(@active, do: "currentColor", else: "none")}
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linejoin="round"
      />
      <path
        d="M9.5 9c0-1.9 1.9-2.2 1.9-4.3M13.3 9c0-1.9 1.9-2.2 1.9-4.3"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
      />
    </svg>
    """
  end

  # Class names are written out in full so Tailwind generates both variants.
  @section_icons %{
    "plan" => {"hero-calendar-days", "hero-calendar-days-solid"},
    "recipes" => {"hero-book-open", "hero-book-open-solid"},
    "shopping" => {"hero-shopping-bag", "hero-shopping-bag-solid"},
    "household" => {"hero-home", "hero-home-solid"}
  }

  defp section_icon(assigns) do
    {outline, solid} = Map.fetch!(@section_icons, assigns.id)
    assigns = assign(assigns, :name, if(assigns.active, do: solid, else: outline))

    ~H"""
    <.icon name={@name} class={@class} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex w-1/3 cursor-pointer justify-center p-2.5"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="Theme: follow the device"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex w-1/3 cursor-pointer justify-center p-2.5"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Theme: light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex w-1/3 cursor-pointer justify-center p-2.5"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Theme: dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
