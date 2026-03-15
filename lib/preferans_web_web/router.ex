defmodule PreferansWebWeb.Router do
  use PreferansWebWeb, :router

  import PreferansWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PreferansWebWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PreferansWebWeb do
    pipe_through :browser

    live_session :public,
      on_mount: [{PreferansWeb.UserAuth, :mount_current_scope}] do
      live "/", PageLive, :index
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:preferans_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PreferansWebWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", PreferansWebWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{PreferansWeb.UserAuth, :require_authenticated}] do
      live "/lobby", LobbyLive, :index
      live "/game/:id", GameLive, :play
      live "/history", HistoryLive, :index
      live "/history/:id", ReplayLive, :show
      live "/profile", ProfileLive, :edit
    end
  end

  scope "/", PreferansWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_settings,
      on_mount: [{PreferansWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", PreferansWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{PreferansWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
