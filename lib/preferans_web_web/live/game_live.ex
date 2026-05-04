defmodule PreferansWebWeb.GameLive do
  use PreferansWebWeb, :live_view

  import PreferansWebWeb.CardComponent
  import PreferansWebWeb.GameComponents, only: [debug_panel: 1]
  import PreferansWebWeb.PhasePanels
  import PreferansWebWeb.Scoresheet
  import PreferansWebWeb.SeatPanel

  alias PreferansWeb.Game.{Cards, GameServer}

  @starting_bule 100

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
    case GameServer.deal_next_hand(socket.assigns.game_id) do
      :ok -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Deal failed: #{reason}")}
    end
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
    <div
      id="game-container"
      class="pf-surface-felt"
      style="position: fixed; inset: 0; overflow: hidden; color: #f5e9d4; font-family: var(--font-display);"
    >
      <div style="display: grid; grid-template-columns: 320px 1fr 360px; height: 100vh;">
        <%!-- Left rail --%>
        <div class="pf-side-left" style={side_style(:left)}>
          <.seat_panel
            name={display_name(@view, @positions.left)}
            avatar_color="#5a3a4a"
            card_count={Map.get(@view.opponent_card_counts, @positions.left, 0)}
            tricks={Enum.at(@view.tricks_won, @positions.left)}
            dealer?={@view.dealer == @positions.left}
            declarer?={@view.declarer == @positions.left}
            partner?={partner?(@view, @positions.left)}
            out?={@view.defense_responses[@positions.left] == :ne_dodjem}
            current_action={last_action_text(@view, @positions.left)}
            side={:left}
            lang={:sr}
          />
          <div class="pf-paper" style={paper_wrap_style(0.6)}>
            <.mini_scoresheet
              player_name={display_name(@view, @positions.left)}
              total={total_for_seat(@view, @positions.left)}
              lang={:sr}
            />
          </div>
          <div style="margin-top: 8px; margin-bottom: 14px; align-self: center;">
            <.refe counts={@view.match_refe_counts} per_refe={10} count={3} />
          </div>
        </div>

        <%!-- Center column --%>
        <div
          class="pf-center"
          style="position: relative; display: flex; flex-direction: column; min-width: 0;"
        >
          <%!-- Header --%>
          <div style="display: flex; justify-content: space-between; align-items: center; padding: 14px 24px;">
            <.link
              navigate={~p"/lobby"}
              style="font-family: var(--font-mono); font-size: 11px; color: #d4b57299; letter-spacing: 0.15em; text-decoration: none;"
            >
              ← LOBBY
            </.link>
            <div style="font-family: var(--font-display); font-size: 14px; letter-spacing: 0.3em; color: #d4b572; text-transform: uppercase;">
              Preferans
            </div>
            <div style="display: flex; gap: 14px; align-items: center; font-family: var(--font-mono); font-size: 11px; color: #d4b57299; letter-spacing: 0.1em;">
              <div :if={@view.game_type}>
                IGRA: <span style="color: #d4b572;">{format_contract(@view)}</span>
                <span :if={@view.kontra_level > 0} style="color: #d96666; margin-left: 8px;">
                  ×{Integer.pow(2, @view.kontra_level)}
                </span>
              </div>
              <div>
                ŠTIH {min(
                  (@view.trick_number || 0) + if(@view.phase == :trick_play, do: 1, else: 0),
                  10
                )}/10
              </div>
              <button
                phx-click="toggle_debug"
                style={debug_toggle_style(@show_debug)}
              >
                DEBUG
              </button>
            </div>
          </div>

          <%!-- Talon (visible during bid + discard before declarer takes) --%>
          <div
            :if={show_talon?(@view)}
            style="display: flex; justify-content: center; gap: 8px; padding: 4px 0;"
          >
            <.card
              :for={i <- 0..1}
              card={Enum.at(@view.talon || [], i)}
              face={if @view.talon && Enum.at(@view.talon, i), do: :up, else: :down}
              size={:md}
            />
          </div>

          <%!-- Phase content --%>
          <div style="flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 16px 24px; gap: 16px;">
            <%= case @view.phase do %>
              <% :bid -> %>
                <.bidding_panel view={@view} lang={:sr} />
              <% :discard -> %>
                <.discard_panel view={@view} selected={@selected_discards} lang={:sr} />
              <% :declare_game -> %>
                <.declare_panel view={@view} lang={:sr} />
              <% :defense -> %>
                <.defense_panel view={@view} lang={:sr} />
              <% :kontra -> %>
                <.kontra_panel view={@view} lang={:sr} />
              <% :trick_play -> %>
                <.trick_area view={@view} positions={@positions} lang={:sr} />
              <% :hand_over -> %>
                <.scoring_panel view={@view} lang={:sr} />
              <% _ -> %>
                <div style="color: #d4b57299; font-family: var(--font-mono); font-size: 12px; letter-spacing: 0.15em;">
                  …
                </div>
            <% end %>
          </div>

          <%!-- Human hand row --%>
          <div style="padding: 14px 24px 20px; display: flex; flex-direction: column; align-items: center; gap: 8px; min-height: 200px;">
            <div style="font-family: var(--font-mono); font-size: 10px; color: #d4b57299; letter-spacing: 0.2em; text-transform: uppercase;">
              {display_name(@view, @seat)}
              <span :if={@view.declarer == @seat} style="color: #d4b572;"> · IGRA</span>
              <span :if={partner?(@view, @seat)} style="color: #d4b572;"> · POZIV</span>
              <span :if={@view.dealer == @seat}> · DELE</span>
              <span :if={@view.is_my_turn} style="color: #d4b572;"> · NA POTEZU</span>
            </div>

            <div style="display: flex; gap: 6px; align-items: baseline; font-family: var(--font-mono);">
              <div style="font-size: 10px; color: #d4b57299; text-transform: uppercase; letter-spacing: 0.15em;">
                Štih
              </div>
              <div style={"font-family: var(--font-display); font-size: 18px; font-weight: 700; color: #{if Enum.at(@view.tricks_won, @seat) > 0, do: "#d4b572", else: "#d4b57266"};"}>
                {Enum.at(@view.tricks_won, @seat)}<span style="font-size: 12px; opacity: 0.5;">/10</span>
              </div>
            </div>

            <div style="position: relative; display: flex; justify-content: center; min-height: 116px;">
              <div
                :for={{c, i} <- Enum.with_index(@view.my_hand)}
                style={"margin-left: #{if i == 0, do: 0, else: -22}px; z-index: #{i}; position: relative;"}
              >
                <% legal? = legal_for_human?(@view, c) %>
                <% selected? = MapSet.member?(@selected_discards, c) %>
                <% clickable? =
                  (@view.phase == :discard and @view.declarer == @seat) or
                    (@view.phase == :trick_play and legal?) %>
                <% click_event =
                  cond do
                    @view.phase == :discard and @view.declarer == @seat -> "toggle_discard"
                    @view.phase == :trick_play and legal? -> "play_card"
                    true -> nil
                  end %>
                <.card
                  card={c}
                  size={:lg}
                  selected={selected?}
                  dimmed={
                    (@view.phase == :trick_play and not legal?) or
                      (@view.phase == :discard and @view.declarer == @seat and
                         MapSet.size(@selected_discards) >= 2 and not selected?)
                  }
                  clickable={clickable?}
                  click_event={click_event}
                  click_value={Cards.card_to_key(c)}
                  id={"#{card_id_prefix(@view)}-#{elem(c, 0)}-#{elem(c, 1)}"}
                />
              </div>
              <div
                :if={@view.my_hand == []}
                style="color: #d4b57266; font-family: var(--font-mono); font-size: 12px; padding: 40px;"
              >
                kraj ruke
              </div>
            </div>
          </div>
        </div>

        <%!-- Right rail --%>
        <div class="pf-side-right" style={side_style(:right)}>
          <.seat_panel
            name={display_name(@view, @positions.right)}
            avatar_color="#3a4a5a"
            card_count={Map.get(@view.opponent_card_counts, @positions.right, 0)}
            tricks={Enum.at(@view.tricks_won, @positions.right)}
            dealer?={@view.dealer == @positions.right}
            declarer?={@view.declarer == @positions.right}
            partner?={partner?(@view, @positions.right)}
            out?={@view.defense_responses[@positions.right] == :ne_dodjem}
            current_action={last_action_text(@view, @positions.right)}
            side={:right}
            lang={:sr}
          />
          <div class="pf-paper" style={paper_wrap_style(-0.5)}>
            <.mini_scoresheet
              player_name={display_name(@view, @positions.right)}
              total={total_for_seat(@view, @positions.right)}
              lang={:sr}
            />
          </div>
          <div class="pf-paper" style={paper_wrap_style(0.4)}>
            <.mini_scoresheet
              player_name={display_name(@view, @seat)}
              total={total_for_seat(@view, @seat)}
              lang={:sr}
            />
          </div>
        </div>
      </div>

      <%!-- Debug panel overlay --%>
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

  defp partner?(view, seat) do
    seat != view.declarer and view.defense_responses[seat] in [:poziv, :idemo_zajedno]
  end

  defp total_for_seat(view, seat) do
    Enum.at(view.match_bule, seat, @starting_bule) - @starting_bule
  end

  defp last_action_text(view, seat) do
    cond do
      view.phase == :bid ->
        view.bid_history
        |> Enum.reverse()
        |> Enum.find_value(fn entry ->
          if entry.player == seat, do: bid_action_short(entry.action)
        end)

      true ->
        case view.defense_responses[seat] do
          :dodjem -> "Dođem"
          :ne_dodjem -> "Ne dođem"
          :poziv -> "Poziv"
          :sam -> "Sam"
          :idemo_zajedno -> "Idemo"
          _ -> nil
        end
    end
  end

  defp bid_action_short(:dalje), do: "Dalje"
  defp bid_action_short({:bid, 2}), do: "Pik"
  defp bid_action_short({:bid, 3}), do: "Karo"
  defp bid_action_short({:bid, 4}), do: "Herc"
  defp bid_action_short({:bid, 5}), do: "Tref"
  defp bid_action_short({:bid, 6}), do: "Betl"
  defp bid_action_short({:bid, 7}), do: "Sans"
  defp bid_action_short(:moje), do: "Moje"
  defp bid_action_short({:moje, _}), do: "Moje"
  defp bid_action_short(:igra), do: "Igra"
  defp bid_action_short(:igra_betl), do: "Igra Betl"
  defp bid_action_short(:igra_sans), do: "Igra Sans"
  defp bid_action_short(_), do: nil

  defp card_id_prefix(%{phase: :discard}), do: "discard"
  defp card_id_prefix(_), do: "hand"

  defp legal_for_human?(view, card) do
    Enum.any?(view.legal_actions, fn
      {:play, c} -> c == card
      _ -> false
    end)
  end

  defp format_contract(view) do
    name =
      case view.game_type do
        :pik -> "Pik"
        :karo -> "Karo"
        :herc -> "Herc"
        :tref -> "Tref"
        :betl -> "Betl"
        :sans -> "Sans"
        _ -> ""
      end

    if view.game_type in [:pik, :karo, :herc, :tref] do
      name <> " " <> Cards.suit_symbol(view.game_type)
    else
      name
    end
  end

  defp side_style(side) do
    border = if side == :left, do: "border-right", else: "border-left"

    """
    background: linear-gradient(180deg, rgba(0,0,0,0.18), rgba(0,0,0,0.05));
    #{border}: 1px solid rgba(212,181,114,0.12);
    overflow: auto;
    display: flex; flex-direction: column;
    """
  end

  defp paper_wrap_style(rotation) do
    """
    margin-top: 8px; margin-left: 8px; margin-right: 8px;
    transform: rotate(#{rotation}deg);
    align-self: center;
    """
  end

  defp debug_toggle_style(true) do
    "background: #d4b572; color: #2a1d10; border: 1px solid #d4b572; padding: 2px 8px; font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.15em; cursor: pointer; border-radius: 3px;"
  end

  defp debug_toggle_style(false) do
    "background: transparent; color: #d4b57299; border: 1px solid #d4b57244; padding: 2px 8px; font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.15em; cursor: pointer; border-radius: 3px;"
  end
end
