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
         show_scoring: false,
         show_debug: false,
         debug_state: nil
       ), layout: false}
    else
      {:ok, socket |> put_flash(:error, "Game not found") |> redirect(to: ~p"/lobby")}
    end
  end

  ## PubSub handlers

  @impl true
  def handle_info({:game_state_updated, _game_id}, socket) do
    {:ok, view} = GameServer.get_player_view(socket.assigns.game_id, socket.assigns.seat)
    socket = assign(socket, :view, view)

    socket =
      if socket.assigns.show_debug do
        {:ok, debug} = GameServer.get_debug_state(socket.assigns.game_id, socket.assigns.seat)
        assign(socket, :debug_state, debug)
      else
        socket
      end

    {:noreply, socket}
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
    submit(socket, :dalje)
  end

  @impl true
  def handle_event("bid_value", %{"bid" => value}, socket) do
    submit(socket, {:bid, String.to_integer(value)})
  end

  @impl true
  def handle_event("bid_moje", _params, socket) do
    submit(socket, :moje)
  end

  @impl true
  def handle_event("bid_igra", %{"action" => action_str}, socket) do
    submit(socket, String.to_existing_atom(action_str))
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
    socket = assign(socket, selected_discards: MapSet.new())
    submit(socket, {:discard, card1, card2})
  end

  @impl true
  def handle_event("declare_game", %{"game" => game_str}, socket) do
    submit(socket, {:declare, String.to_existing_atom(game_str)})
  end

  @impl true
  def handle_event("defense", %{"action" => action_str}, socket) do
    submit(socket, String.to_existing_atom(action_str))
  end

  @impl true
  def handle_event("kontra", %{"action" => action_str}, socket) do
    submit(socket, String.to_existing_atom(action_str))
  end

  @impl true
  def handle_event("next_hand", _params, socket) do
    GameServer.deal_next_hand(socket.assigns.game_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("play_card", %{"card" => card_str}, socket) do
    submit(socket, {:play, Cards.parse_card_key(card_str)})
  end

  @impl true
  def handle_event("toggle_debug", _params, socket) do
    show = !socket.assigns.show_debug

    socket =
      if show do
        {:ok, debug} = GameServer.get_debug_state(socket.assigns.game_id, socket.assigns.seat)
        assign(socket, show_debug: true, debug_state: debug)
      else
        assign(socket, show_debug: false, debug_state: nil)
      end

    {:noreply, socket}
  end

  defp submit(socket, action) do
    case GameServer.submit_action(socket.assigns.game_id, socket.assigns.seat, action) do
      :ok -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Action failed: #{reason}")}
    end
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
          <div class="flex items-center gap-3">
            <div class="text-green-300/50 text-xs">
              {phase_label(@view.phase)}
            </div>
            <button
              phx-click="toggle_debug"
              class={[
                "text-xs px-2 py-0.5 rounded",
                @show_debug && "bg-amber-600 text-white",
                !@show_debug && "bg-gray-700 text-gray-400 hover:text-gray-200"
              ]}
            >
              Debug
            </button>
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
              is_dealer={@view.dealer == @positions.left}
              position={:left}
              open_hand={Map.get(@view.defender_hands, @positions.left)}
              playable_cards={defender_playable(@view, @positions.left)}
            />
            <.opponent_area
              name={display_name(@view, @positions.right)}
              card_count={Map.get(@view.opponent_card_counts, @positions.right, 0)}
              tricks={Enum.at(@view.tricks_won, @positions.right)}
              is_current={@view.current_player == @positions.right}
              is_declarer={@view.declarer == @positions.right}
              is_dealer={@view.dealer == @positions.right}
              position={:right}
              open_hand={Map.get(@view.defender_hands, @positions.right)}
              playable_cards={defender_playable(@view, @positions.right)}
            />
          </div>

          <%!-- Center area --%>
          <div class="flex flex-col items-center gap-4">
            <%!-- Talon --%>
            <div :if={show_talon?(@view)} class="flex gap-2 mb-2">
              <div class="text-green-300/50 text-xs text-center mb-1 w-full">Talon</div>
              <div class="flex gap-2">
                <.card
                  :for={{c, i} <- Enum.with_index(@view.talon || [nil, nil])}
                  id={if c, do: "talon-#{elem(c, 0)}-#{elem(c, 1)}", else: "talon-back-#{i}"}
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
              <% :kontra -> %>
                <.kontra_phase view={@view} />
              <% :trick_play -> %>
                <.trick_play_phase view={@view} positions={@positions} />
              <% :hand_over -> %>
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
              <span :if={@view.dealer == @seat} class="text-green-400/70 text-2xl">
                {gettext("Ⓓ")}
              </span>
              <span
                :if={@view.declarer == @seat}
                class="bg-red-600 text-white text-xs font-bold uppercase px-1.5 py-0.5 rounded"
              >
                {gettext("IGRAC")}
              </span>
            </div>

            <div :if={@view.phase != :discard or @view.declarer != @seat}>
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

      <%!-- Debug panel --%>
      <.debug_panel :if={@show_debug && @debug_state} debug_state={@debug_state} />
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
    # Engine's counter-clockwise order is +1, +2. To display correctly:
    # seat+1 goes on the RIGHT (next counter-clockwise), seat+2 on the LEFT.
    %{
      right: rem(my_seat + 1, 3),
      left: rem(my_seat + 2, 3),
      bottom: my_seat
    }
  end

  defp display_name(view, seat) do
    Map.get(view.display_names, seat, "Seat #{seat}")
  end

  defp show_talon?(view) do
    view.phase == :bid or (view.phase == :discard and view.talon != nil)
  end

  # In Sans/Betl, when it's a defender's turn, the declarer picks their card
  defp defender_playable(view, defender_seat) do
    if view.current_player == defender_seat and
         view.is_my_turn and
         view.current_player != view.my_seat and
         map_size(view.defender_hands) > 0 do
      view.legal_actions
      |> Enum.filter(&match?({:play, _}, &1))
      |> Enum.map(fn {:play, card} -> card end)
      |> MapSet.new()
    else
      nil
    end
  end

  defp phase_label(:bid), do: "Bidding"
  defp phase_label(:discard), do: "Discard"
  defp phase_label(:declare_game), do: "Declare"
  defp phase_label(:defense), do: "Defense"
  defp phase_label(:kontra), do: "Kontra"
  defp phase_label(:trick_play), do: "Trick Play"
  defp phase_label(:hand_over), do: "Hand Over"
  defp phase_label(_), do: ""
end
