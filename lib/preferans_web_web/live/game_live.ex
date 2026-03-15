defmodule PreferansWebWeb.GameLive do
  use PreferansWebWeb, :live_view

  import PreferansWebWeb.CardComponent
  import PreferansWebWeb.GameComponents

  alias PreferansWeb.Game.{Cards, GameServer}

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    if GameServer.game_exists?(game_id) do
      seat = determine_seat(game_id, socket.assigns.current_scope.user)

      if connected?(socket) do
        GameServer.subscribe(game_id)
      end

      {:ok, view} = GameServer.get_player_view(game_id, seat)
      positions = seat_positions(seat)

      {:ok,
       assign(socket,
         game_id: game_id,
         seat: seat,
         view: view,
         positions: positions,
         selected_discards: MapSet.new(),
         show_scoring: false
       ), layout: false}
    else
      {:ok, socket |> put_flash(:error, "Game not found") |> redirect(to: ~p"/lobby")}
    end
  end

  ## PubSub handlers

  @impl true
  def handle_info({:game_state_updated, _game_id}, socket) do
    {:ok, view} = GameServer.get_player_view(socket.assigns.game_id, socket.assigns.seat)
    {:noreply, assign(socket, :view, view)}
  end

  @impl true
  def handle_info({:hand_completed, _game_id, _scoring_result}, socket) do
    {:ok, view} = GameServer.get_player_view(socket.assigns.game_id, socket.assigns.seat)
    {:noreply, assign(socket, view: view, show_scoring: true)}
  end

  @impl true
  def handle_info({:new_hand_starting, _game_id}, socket) do
    {:ok, view} = GameServer.get_player_view(socket.assigns.game_id, socket.assigns.seat)
    {:noreply, assign(socket, view: view, show_scoring: false, selected_discards: MapSet.new())}
  end

  @impl true
  def handle_info({:match_ended, _game_id, _final_scores}, socket) do
    {:ok, view} = GameServer.get_player_view(socket.assigns.game_id, socket.assigns.seat)
    {:noreply, assign(socket, :view, view)}
  end

  @impl true
  def handle_info({:action_played, _game_id, _seat, _action}, socket) do
    {:noreply, socket}
  end

  ## Event handlers

  @impl true
  def handle_event("bid", %{"action" => "dalje"}, socket) do
    GameServer.submit_action(socket.assigns.game_id, socket.assigns.seat, :dalje)
    {:noreply, socket}
  end

  @impl true
  def handle_event("bid", %{"action" => "bid", "value" => value}, socket) do
    v = String.to_integer(value)
    GameServer.submit_action(socket.assigns.game_id, socket.assigns.seat, {:bid, v})
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_discard", %{"card" => card_str}, socket) do
    card = Cards.parse_card_key(card_str)
    selected = socket.assigns.selected_discards

    selected =
      if MapSet.member?(selected, card) do
        MapSet.delete(selected, card)
      else
        if MapSet.size(selected) < 2, do: MapSet.put(selected, card), else: selected
      end

    {:noreply, assign(socket, selected_discards: selected)}
  end

  @impl true
  def handle_event("confirm_discard", _params, socket) do
    [card1, card2] = MapSet.to_list(socket.assigns.selected_discards)

    GameServer.submit_action(
      socket.assigns.game_id,
      socket.assigns.seat,
      {:discard, card1, card2}
    )

    {:noreply, assign(socket, selected_discards: MapSet.new())}
  end

  @impl true
  def handle_event("declare_game", %{"game" => game_str}, socket) do
    game = String.to_existing_atom(game_str)
    GameServer.submit_action(socket.assigns.game_id, socket.assigns.seat, game)
    {:noreply, socket}
  end

  @impl true
  def handle_event("defense", %{"action" => action_str}, socket) do
    action = String.to_existing_atom(action_str)
    GameServer.submit_action(socket.assigns.game_id, socket.assigns.seat, action)
    {:noreply, socket}
  end

  @impl true
  def handle_event("play_card", %{"card" => card_str}, socket) do
    card = Cards.parse_card_key(card_str)
    GameServer.submit_action(socket.assigns.game_id, socket.assigns.seat, {:play, card})
    {:noreply, socket}
  end

  ## Render

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen w-screen overflow-hidden" id="game-container">
      <%!-- Game table --%>
      <div class="flex-1 game-table flex flex-col">
        <%!-- Top bar --%>
        <div class="flex justify-between items-center px-4 py-2">
          <.link navigate={~p"/lobby"} class="text-green-300/60 text-sm hover:text-green-200">
            ← {gettext("Back to Lobby")}
          </.link>
          <div class="text-green-300/50 text-xs">
            {phase_label(@view.phase)}
          </div>
        </div>

        <%!-- Main table area --%>
        <div class="flex-1 flex flex-col items-center justify-between px-8 py-4">
          <%!-- Opponents row --%>
          <div class="flex justify-between w-full max-w-3xl">
            <.opponent_area
              name={display_name(@view, @positions.left)}
              card_count={Map.get(@view.opponent_card_counts, @positions.left, 0)}
              tricks={Enum.at(@view.tricks_won, @positions.left)}
              is_current={@view.current_player == @positions.left}
              is_declarer={@view.declarer == @positions.left}
              position={:left}
            />
            <.opponent_area
              name={display_name(@view, @positions.right)}
              card_count={Map.get(@view.opponent_card_counts, @positions.right, 0)}
              tricks={Enum.at(@view.tricks_won, @positions.right)}
              is_current={@view.current_player == @positions.right}
              is_declarer={@view.declarer == @positions.right}
              position={:right}
            />
          </div>

          <%!-- Center area --%>
          <div class="flex flex-col items-center gap-4">
            <%!-- Talon --%>
            <div :if={show_talon?(@view)} class="flex gap-2 mb-2">
              <div class="text-green-300/50 text-xs text-center mb-1 w-full">Talon</div>
              <div class="flex gap-2">
                <.card
                  :for={c <- @view.talon || [nil, nil]}
                  card={c}
                  face={if @view.talon, do: :up, else: :down}
                  size={:small}
                />
              </div>
            </div>

            <%!-- Phase content --%>
            <%= case @view.phase do %>
              <% :bid -> %>
                <.bidding_phase view={@view} />
              <% :discard -> %>
                <.discard_phase view={@view} selected={@selected_discards} />
              <% :declare_game -> %>
                <.declare_game_phase view={@view} />
              <% :defense -> %>
                <.defense_phase view={@view} />
              <% :trick_play -> %>
                <.trick_play_phase view={@view} positions={@positions} />
              <% phase when phase in [:scoring, :hand_over] -> %>
                <.scoring_phase view={@view} />
              <% _ -> %>
                <div class="text-green-200/60 text-sm">{gettext("Waiting...")}</div>
            <% end %>
          </div>

          <%!-- Player's hand --%>
          <div class="flex flex-col items-center gap-2 pb-4">
            <div class="flex items-center gap-1.5 text-sm text-green-100">
              <span class={[
                "w-2 h-2 rounded-full",
                @view.is_my_turn && "bg-amber-400",
                !@view.is_my_turn && "bg-transparent"
              ]} />
              <span class="font-medium">{display_name(@view, @seat)}</span>
              <span :if={@view.declarer == @seat} class="text-amber-300 text-xs">(D)</span>
            </div>

            <div :if={@view.phase != :discard}>
              <.my_hand view={@view} phase_clickable={@view.phase == :trick_play} />
            </div>

            <div class="text-xs text-green-200/70">
              {gettext("Tricks: %{count}", count: Enum.at(@view.tricks_won, @seat))}
            </div>
          </div>
        </div>
      </div>

      <%!-- Scoring sidebar --%>
      <.scoring_sidebar view={@view} />
    </div>
    """
  end

  ## Private helpers

  defp determine_seat(game_id, user) do
    {:ok, view} = GameServer.get_player_view(game_id, 0)

    found =
      Enum.find(view.players, fn p ->
        Map.get(p, :user_id) == user.id
      end)

    if found, do: found.seat, else: 0
  end

  defp seat_positions(my_seat) do
    %{
      left: rem(my_seat + 1, 3),
      right: rem(my_seat + 2, 3),
      bottom: my_seat
    }
  end

  defp display_name(view, seat) do
    Map.get(view.display_names, seat, "Seat #{seat}")
  end

  defp show_talon?(view) do
    view.phase in [:bid, :discard, :declare_game] or
      (view.talon != nil and view.phase not in [:trick_play, :scoring, :hand_over])
  end

  defp phase_label(:bid), do: "Bidding"
  defp phase_label(:discard), do: "Discard"
  defp phase_label(:declare_game), do: "Declare"
  defp phase_label(:defense), do: "Defense"
  defp phase_label(:trick_play), do: "Trick Play"
  defp phase_label(:scoring), do: "Scoring"
  defp phase_label(:hand_over), do: "Hand Over"
  defp phase_label(_), do: ""
end
