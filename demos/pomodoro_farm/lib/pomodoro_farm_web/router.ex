defmodule PomodoroFarmWeb.Router do
  use PomodoroFarmWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PomodoroFarmWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", PomodoroFarmWeb do
    pipe_through :browser
    live "/", TimersLive
  end
end
