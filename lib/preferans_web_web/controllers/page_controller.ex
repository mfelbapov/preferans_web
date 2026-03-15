defmodule PreferansWebWeb.PageController do
  use PreferansWebWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
