defmodule PreferansWebWeb.LobbyLive do
  use PreferansWebWeb, :live_view

  alias PreferansWeb.Game

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    active_game = Game.find_user_active_game(user.id)

    {:ok,
     assign(socket,
       active_game: active_game,
       user: user
     )}
  end

  @impl true
  def handle_event("new_game", _params, socket) do
    user = socket.assigns.user

    case Game.start_solo_game(user.id) do
      {:ok, game_id} ->
        {:noreply, push_navigate(socket, to: ~p"/game/#{game_id}")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not start game"))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-lg">
        <.header>
          {gettext("Lobby")}
          <:subtitle>{gettext("Welcome, %{name}", name: @user.username || @user.email)}</:subtitle>
        </.header>

        <div class="mt-8 space-y-6">
          <%!-- Player stats --%>
          <div class="grid grid-cols-2 gap-4">
            <div class="bg-base-200 rounded-lg p-4 text-center">
              <div class="text-2xl font-bold">{@user.games_played}</div>
              <div class="text-sm text-base-content/60">{gettext("Games Played")}</div>
            </div>
            <div class="bg-base-200 rounded-lg p-4 text-center">
              <div class="text-2xl font-bold">{@user.rating}</div>
              <div class="text-sm text-base-content/60">{gettext("Rating")}</div>
            </div>
          </div>

          <%!-- Game actions --%>
          <div class="space-y-3">
            <.link
              :if={@active_game}
              navigate={~p"/game/#{@active_game}"}
              class="btn btn-primary w-full"
            >
              {gettext("Continue Game")}
            </.link>

            <button phx-click="new_game" class="btn btn-primary w-full" id="new-game-btn">
              {gettext("New Game (vs 2 AI)")}
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
