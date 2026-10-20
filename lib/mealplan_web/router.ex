defmodule MealplanWeb.Router do
  use MealplanWeb, :router
  use ErrorTracker.Web, :router

  import MealplanWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MealplanWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "cross-origin-opener-policy" => "same-origin",
      "permissions-policy" => "camera=(), microphone=(), geolocation=(), payment=()"
    }

    plug MealplanWeb.Plugs.ContentSecurityPolicy
    plug :fetch_current_scope_for_user
  end

  # LiveDashboard and the mailbox preview use inline scripts and styles, so
  # these dev-only tools are served without our strict CSP.
  pipeline :dev_tools do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MealplanWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", MealplanWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:mealplan, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :dev_tools

      live_dashboard "/dashboard", metrics: MealplanWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Admin routes

  # Logged-in admins only. Non-admins get a 404 from :require_admin; the
  # LiveView mount re-checks via the :require_admin on_mount hook.
  scope "/admin" do
    pipe_through [:browser, :require_authenticated_user, :require_admin]

    error_tracker_dashboard "/errors",
      on_mount: [{MealplanWeb.UserAuth, :require_admin}],
      csp_nonce_assign_key: :csp_nonce
  end

  ## Authentication routes

  scope "/", MealplanWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{MealplanWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      # Needs a login but not a household: this is where you get one.
      live "/welcome", HouseholdLive.Onboarding, :new
    end

    # Everything that works on a household's data. Users without one are sent
    # to /welcome.
    live_session :require_household,
      on_mount: [
        {MealplanWeb.UserAuth, :require_authenticated},
        {MealplanWeb.UserAuth, :require_household}
      ] do
      live "/plan", PlanLive.Week, :index
      live "/household", HouseholdLive.Settings, :edit
      live "/recipes", RecipeLive.Index, :index
      live "/recipes/new", RecipeLive.Form, :new
      live "/recipes/:id", RecipeLive.Show, :show
      live "/recipes/:id/edit", RecipeLive.Form, :edit
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", MealplanWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{MealplanWeb.UserAuth, :mount_current_scope}] do
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
