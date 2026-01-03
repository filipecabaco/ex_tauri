defmodule ExampleDesktopWeb.Router do
  use ExampleDesktopWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExampleDesktopWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ExampleDesktopWeb do
    pipe_through :browser

    live "/", NotesLive
  end

  # Tauri heartbeat endpoint - no CSRF protection needed
  scope "/_tauri" do
    pipe_through :api

    get "/heartbeat", ExampleDesktopWeb.TauriController, :heartbeat
  end
end
