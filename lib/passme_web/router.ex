defmodule PassmeWeb.Router do
  use PassmeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PassmeWeb do
    pipe_through :browser

    get "/", PageController, :index
    get "/login", PageController, :login
  end

  # Other scopes may use custom stacks.
  # scope "/api", PassmeWeb do
  #   pipe_through :api
  # end
end
