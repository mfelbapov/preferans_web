defmodule PreferansWebWeb.LobbyLive do
  use PreferansWebWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>Lobby</.header>
    </Layouts.app>
    """
  end
end
