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

  scope "/", ExampleDesktopWeb do
    pipe_through :browser

    live "/", NotesLive
  end
end
