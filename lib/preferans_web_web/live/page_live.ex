defmodule PreferansWebWeb.PageLive do
  use PreferansWebWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>Preferans</.header>
        <p class="mt-4">Welcome to Preferans — the classic card game.</p>
      </div>
    </Layouts.app>
    """
  end
end
