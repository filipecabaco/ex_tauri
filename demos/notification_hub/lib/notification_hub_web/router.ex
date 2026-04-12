defmodule NotificationHubWeb.Router do
  use NotificationHubWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {NotificationHubWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", NotificationHubWeb do
    pipe_through :browser
    live "/", InboxLive
  end
end
