# Claude Code Prompt: Preferans Phoenix LiveView UI

## Context

We have a C++ game engine that runs as a JSON server binary (`preferans_server`).
It reads JSON commands from stdin and writes JSON responses to stdout.
The Phoenix app spawns this binary as an Erlang Port and communicates via JSON.

The full JSON protocol is defined in the engine repo's SERVER_PROMPT.md.
Key commands: new_game, action, get_state, quit.

## Project Setup

Create a new Phoenix project if not already done:
```bash
mix phx.new preferans_web --live
cd preferans_web
mix deps.get
mix ecto.create
```

## Architecture

```
┌──────────────────────────────────────────────────┐
│                  Phoenix App                      │
│                                                    │
│  ┌─────────────┐     ┌──────────────────────┐    │
│  │  LiveView    │────▶│  GameServer           │    │
│  │  (per user)  │◀────│  (GenServer, 1 per    │    │
│  │              │     │   active game)         │    │
│  └─────────────┘     └──────┬───────────────┘    │
│                              │                     │
│                              │ JSON over stdin/out  │
│                              ▼                     │
│                     ┌──────────────────────┐      │
│                     │  preferans_server     │      │
│                     │  (C++ Port process)   │      │
│                     └──────────────────────┘      │
└──────────────────────────────────────────────────┘
```

## Step 1: GameServer GenServer

Create `lib/preferans_web/game/game_server.ex`

This GenServer manages one active game. It owns the C++ Port process,
sends commands, receives responses, and broadcasts state updates via PubSub.

```elixir
defmodule PreferansWeb.GameServer do
  use GenServer

  @server_path Application.compile_env(:preferans_web, :server_path, 
    "./priv/bin/preferans_server")
  @model_dir Application.compile_env(:preferans_web, :model_dir,
    "./priv/models/")

  # Public API
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  def new_game(pid, config), do: GenServer.call(pid, {:new_game, config})
  def player_action(pid, action), do: GenServer.call(pid, {:action, action})
  def get_state(pid), do: GenServer.call(pid, :get_state)

  # Callbacks
  def init(opts) do
    port = Port.open(
      {:spawn, "#{@server_path} --model-dir #{@model_dir}"},
      [:binary, :line, :use_stdio, :exit_status]
    )
    {:ok, %{
      port: port,
      game_id: nil,
      game_topic: opts[:topic] || "game:#{:erlang.unique_integer([:positive])}",
      human_seat: opts[:human_seat] || 0
    }}
  end

  def handle_call({:new_game, config}, _from, state) do
    response = send_command(state.port, %{cmd: "new_game", config: config})
    new_state = %{state | game_id: response["game_id"]}
    broadcast(new_state.game_topic, {:game_started, response["state"]})
    {:reply, {:ok, response["state"]}, new_state}
  end

  def handle_call({:action, action}, _from, state) do
    response = send_command(state.port, %{
      cmd: "action",
      game_id: state.game_id,
      action: action
    })
    
    case response["status"] do
      "ok" ->
        broadcast(state.game_topic, {:state_updated, response})
        {:reply, {:ok, response}, state}
      "error" ->
        {:reply, {:error, response["message"]}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    response = send_command(state.port, %{
      cmd: "get_state",
      game_id: state.game_id
    })
    {:reply, {:ok, response["state"]}, state}
  end

  def terminate(_reason, state) do
    send_command(state.port, %{cmd: "quit"})
    Port.close(state.port)
  end

  # Private helpers
  defp send_command(port, cmd) do
    Port.command(port, Jason.encode!(cmd) <> "\n")
    receive do
      {^port, {:data, line}} -> Jason.decode!(line)
    after
      10_000 -> %{"status" => "error", "message" => "Server timeout"}
    end
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(PreferansWeb.PubSub, topic, message)
  end
end
```

## Step 2: Game LiveView

Create `lib/preferans_web/live/game_live.ex`

This is the main game interface. One LiveView per player.

### Layout

```
┌─────────────────────────────────────────────────────┐
│                    Opponent 2 (top)                   │
│              [? ] [? ] [? ] [? ] [? ]                │
│              [? ] [? ] [? ] [? ] [? ]                │
│                                                       │
│                                                       │
│   Opponent 1          ┌─────────┐        Info Panel   │
│   (left)              │  Table  │        - Phase      │
│   [?][?][?]           │  area   │        - Trump      │
│   [?][?][?]           │ (tricks)│        - Score      │
│   [?][?][?]           │         │        - Bule       │
│   [?]                 └─────────┘        - Refes      │
│                                                       │
│                                                       │
│              Your hand (bottom, face up)              │
│         [A♠] [K♠] [Q♥] [9♥] [7♥] [A♦]              │
│         [K♦] [8♦] [9♣] [7♣]                         │
│                                                       │
│   ┌─────────────────────────────────────────────┐    │
│   │  Action bar: [Dalje] [Dva] [Tri] [Igra]     │    │
│   └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

### Implementation

```elixir
defmodule PreferansWeb.GameLive do
  use PreferansWeb, :live_view

  alias PreferansWeb.GameServer

  @impl true
  def mount(_params, _session, socket) do
    # Start a new game server
    {:ok, game_pid} = GameServer.start_link(topic: "game:#{socket.id}")
    
    # Subscribe to game updates
    Phoenix.PubSub.subscribe(PreferansWeb.PubSub, "game:#{socket.id}")
    
    # Start a new game: human in seat 0, two AI opponents
    {:ok, state} = GameServer.new_game(game_pid, %{
      "players" => [
        %{"seat" => 0, "type" => "human", "name" => "Player"},
        %{"seat" => 1, "type" => "ai"},
        %{"seat" => 2, "type" => "ai"}
      ]
    })

    {:ok, assign(socket,
      game_pid: game_pid,
      game_state: state,
      events: [],
      selected_cards: [],  # For discard selection
      error_message: nil,
      human_seat: 0
    )}
  end

  @impl true
  def handle_event("bid", %{"value" => value}, socket) do
    action = %{"type" => "bid", "value" => value}
    handle_player_action(action, socket)
  end

  def handle_event("play_card", %{"card" => card}, socket) do
    action = %{"type" => "play_card", "card" => card}
    handle_player_action(action, socket)
  end

  def handle_event("toggle_discard", %{"card" => card}, socket) do
    selected = socket.assigns.selected_cards
    selected = if card in selected do
      List.delete(selected, card)
    else
      if length(selected) < 2, do: selected ++ [card], else: selected
    end
    {:noreply, assign(socket, selected_cards: selected)}
  end

  def handle_event("confirm_discard", _params, socket) do
    cards = socket.assigns.selected_cards
    if length(cards) == 2 do
      action = %{"type" => "discard", "cards" => cards}
      handle_player_action(action, socket)
    else
      {:noreply, assign(socket, error_message: "Select exactly 2 cards")}
    end
  end

  def handle_event("declare_game", %{"game" => game}, socket) do
    action = %{"type" => "declare", "game" => game}
    handle_player_action(action, socket)
  end

  def handle_event("defense", %{"value" => value}, socket) do
    action = %{"type" => "defense", "value" => value}
    handle_player_action(action, socket)
  end

  def handle_event("kontra", %{"value" => value}, socket) do
    action = %{"type" => "kontra", "value" => value}
    handle_player_action(action, socket)
  end

  def handle_event("new_hand", _params, socket) do
    {:ok, state} = GameServer.new_game(socket.assigns.game_pid, %{
      "players" => [
        %{"seat" => 0, "type" => "human"},
        %{"seat" => 1, "type" => "ai"},
        %{"seat" => 2, "type" => "ai"}
      ]
    })
    {:noreply, assign(socket,
      game_state: state,
      events: [],
      selected_cards: [],
      error_message: nil
    )}
  end

  # Handle PubSub broadcasts
  @impl true
  def handle_info({:state_updated, response}, socket) do
    {:noreply, assign(socket,
      game_state: response["state"],
      events: response["events"] || [],
      error_message: nil
    )}
  end

  def handle_info({:game_started, state}, socket) do
    {:noreply, assign(socket, game_state: state)}
  end

  # Private
  defp handle_player_action(action, socket) do
    case GameServer.player_action(socket.assigns.game_pid, action) do
      {:ok, response} ->
        {:noreply, assign(socket,
          game_state: response["state"],
          events: response["events"] || [],
          selected_cards: [],
          error_message: nil
        )}
      {:error, message} ->
        {:noreply, assign(socket, error_message: message)}
    end
  end

  # Template
  @impl true
  def render(assigns) do
    ~H"""
    <div class="game-table">
      <!-- Opponent hands (face down) -->
      <.opponent_hand position="top" cards={opponent_card_count(@game_state, 2)} />
      <.opponent_hand position="left" cards={opponent_card_count(@game_state, 1)} />
      
      <!-- Table center: current trick, talon, game info -->
      <div class="table-center">
        <.trick_display trick={current_trick(@game_state)} />
        <.talon_display talon={@game_state["talon"]} phase={@game_state["phase"]} />
      </div>
      
      <!-- Info panel -->
      <div class="info-panel">
        <.phase_display phase={@game_state["phase"]} />
        <.score_display bule={@game_state["bule"]} refes={@game_state["refes"]} />
        <.game_type_display state={@game_state} />
      </div>
      
      <!-- AI events (animated) -->
      <.event_feed events={@events} />
      
      <!-- Error message -->
      <div :if={@error_message} class="error-toast">
        <%= @error_message %>
      </div>
      
      <!-- Player hand (face up, clickable) -->
      <div class="player-hand">
        <.card_hand 
          cards={my_cards(@game_state, @human_seat)} 
          phase={@game_state["phase"]}
          selected={@selected_cards}
          legal={legal_card_actions(@game_state)}
        />
      </div>
      
      <!-- Action bar (context-dependent) -->
      <div class="action-bar">
        <.action_buttons 
          phase={@game_state["phase"]}
          legal_actions={@game_state["legal_actions"]}
          selected_cards={@selected_cards}
          current_player={@game_state["current_player"]}
          human_seat={@human_seat}
        />
      </div>
    </div>
    """
  end

  # Helper functions
  defp my_cards(state, seat) do
    get_in(state, ["hands", to_string(seat)]) || []
  end

  defp opponent_card_count(state, seat) do
    # Opponents' cards are null, but we know they have 10 (or fewer)
    10  # Adjust based on game phase
  end

  defp current_trick(state) do
    state["current_trick"] || []
  end

  defp legal_card_actions(state) do
    (state["legal_actions"] || [])
    |> Enum.filter(&(&1["type"] == "play_card"))
    |> Enum.map(&(&1["card"]))
  end
end
```

## Step 3: Card Components

Create `lib/preferans_web/components/card_components.ex`

These are the reusable card display components.

```elixir
defmodule PreferansWeb.CardComponents do
  use Phoenix.Component

  # A single playing card (face up)
  attr :card, :string, required: true
  attr :playable, :boolean, default: false
  attr :selected, :boolean, default: false
  attr :on_click, :string, default: nil
  
  def card(assigns) do
    ~H"""
    <div 
      class={[
        "card",
        suit_color(@card),
        @playable && "playable",
        @selected && "selected"
      ]}
      phx-click={@on_click}
      phx-value-card={@card}
    >
      <span class="rank"><%= rank(@card) %></span>
      <span class="suit"><%= suit_symbol(@card) %></span>
    </div>
    """
  end

  # A face-down card
  def card_back(assigns) do
    ~H"""
    <div class="card card-back">
      <div class="card-pattern"></div>
    </div>
    """
  end

  # Player's hand (face up, interactive)
  attr :cards, :list, required: true
  attr :phase, :string, required: true
  attr :selected, :list, default: []
  attr :legal, :list, default: []

  def card_hand(assigns) do
    ~H"""
    <div class="hand">
      <%= for card <- @cards do %>
        <.card 
          card={card}
          playable={card in @legal}
          selected={card in @selected}
          on_click={click_action(@phase, card, @legal)}
        />
      <% end %>
    </div>
    """
  end

  # Opponent's hand (face down)
  attr :position, :string, required: true
  attr :cards, :integer, required: true

  def opponent_hand(assigns) do
    ~H"""
    <div class={"opponent-hand opponent-#{@position}"}>
      <%= for _i <- 1..@cards do %>
        <.card_back />
      <% end %>
    </div>
    """
  end

  # Current trick display
  attr :trick, :list, required: true

  def trick_display(assigns) do
    ~H"""
    <div class="trick-area">
      <%= for {card, player} <- @trick do %>
        <div class={"trick-card trick-seat-#{player}"}>
          <.card card={card} />
        </div>
      <% end %>
    </div>
    """
  end

  # Talon display
  attr :talon, :any, required: true
  attr :phase, :string, required: true

  def talon_display(assigns) do
    ~H"""
    <div class="talon">
      <%= if @talon do %>
        <%= for card <- @talon do %>
          <.card card={card} />
        <% end %>
      <% else %>
        <.card_back />
        <.card_back />
      <% end %>
    </div>
    """
  end

  # Helper functions
  defp rank(card) do
    card |> String.slice(0..-2//1)
  end

  defp suit_symbol(card) do
    case String.last(card) do
      "S" -> "♠"
      "D" -> "♦"
      "H" -> "♥"
      "C" -> "♣"
    end
  end

  defp suit_color(card) do
    case String.last(card) do
      "S" -> "black"
      "C" -> "black"
      "H" -> "red"
      "D" -> "red"
    end
  end

  defp click_action("TRICK_PLAY", card, legal) do
    if card in legal, do: "play_card", else: nil
  end
  defp click_action("DISCARD", _card, _legal), do: "toggle_discard"
  defp click_action(_, _, _), do: nil
end
```

## Step 4: Action Bar Components

Create `lib/preferans_web/components/action_components.ex`

Context-dependent action buttons that change with each game phase.

```elixir
defmodule PreferansWeb.ActionComponents do
  use Phoenix.Component

  attr :phase, :string, required: true
  attr :legal_actions, :list, required: true
  attr :selected_cards, :list, default: []
  attr :current_player, :integer, required: true
  attr :human_seat, :integer, required: true

  def action_buttons(assigns) do
    ~H"""
    <div class="actions">
      <%= if @current_player == @human_seat do %>
        <%= case @phase do %>
          <% "BID" -> %>
            <.bid_buttons actions={@legal_actions} />
          <% "DISCARD" -> %>
            <.discard_buttons selected={@selected_cards} />
          <% "DECLARE_GAME" -> %>
            <.declare_buttons actions={@legal_actions} />
          <% "DEFENSE_DECISION" -> %>
            <.defense_buttons actions={@legal_actions} />
          <% "KONTRA_CHAIN" -> %>
            <.kontra_buttons actions={@legal_actions} />
          <% "TRICK_PLAY" -> %>
            <p class="hint">Click a card to play it</p>
          <% "HAND_OVER" -> %>
            <button phx-click="new_hand" class="btn-primary">
              Next Hand
            </button>
          <% _ -> %>
            <p>Waiting...</p>
        <% end %>
      <% else %>
        <p class="waiting">Opponent is thinking...</p>
      <% end %>
    </div>
    """
  end

  defp bid_buttons(assigns) do
    ~H"""
    <div class="bid-actions">
      <%= for action <- @actions do %>
        <button 
          phx-click="bid" 
          phx-value-value={action["value"]}
          class={"btn-bid btn-#{action["value"]}"}
        >
          <%= bid_label(action["value"]) %>
        </button>
      <% end %>
    </div>
    """
  end

  defp discard_buttons(assigns) do
    ~H"""
    <div class="discard-actions">
      <p>Select 2 cards to discard (<%= length(@selected) %>/2)</p>
      <button 
        phx-click="confirm_discard"
        class="btn-primary"
        disabled={length(@selected) != 2}
      >
        Confirm Discard
      </button>
    </div>
    """
  end

  defp declare_buttons(assigns) do
    ~H"""
    <div class="declare-actions">
      <p>Choose your game:</p>
      <%= for action <- @actions do %>
        <button 
          phx-click="declare_game" 
          phx-value-game={action["game"]}
          class={"btn-declare btn-#{action["game"]}"}
        >
          <%= game_label(action["game"]) %>
        </button>
      <% end %>
    </div>
    """
  end

  defp defense_buttons(assigns) do
    ~H"""
    <div class="defense-actions">
      <%= for action <- @actions do %>
        <button 
          phx-click="defense" 
          phx-value-value={action["value"]}
          class={"btn-defense btn-#{action["value"]}"}
        >
          <%= defense_label(action["value"]) %>
        </button>
      <% end %>
    </div>
    """
  end

  defp kontra_buttons(assigns) do
    ~H"""
    <div class="kontra-actions">
      <%= for action <- @actions do %>
        <button 
          phx-click="kontra" 
          phx-value-value={action["value"]}
          class={"btn-kontra btn-#{action["value"]}"}
        >
          <%= kontra_label(action["value"]) %>
        </button>
      <% end %>
    </div>
    """
  end

  # Labels - bilingual (Serbian / English)
  defp bid_label("dalje"), do: "Dalje (Pass)"
  defp bid_label("2"), do: "Dva (2)"
  defp bid_label("3"), do: "Tri (3)"
  defp bid_label("4"), do: "Četiri (4)"
  defp bid_label("5"), do: "Pet (5)"
  defp bid_label("6"), do: "Betl (6)"
  defp bid_label("7"), do: "Sans (7)"
  defp bid_label("moje"), do: "Moje"
  defp bid_label("igra"), do: "Igra"
  defp bid_label("igra_betl"), do: "Igra Betl"
  defp bid_label("igra_sans"), do: "Igra Sans"
  defp bid_label(other), do: other

  defp game_label("pik"), do: "Pik ♠"
  defp game_label("karo"), do: "Karo ♦"
  defp game_label("herc"), do: "Herc ♥"
  defp game_label("tref"), do: "Tref ♣"
  defp game_label("betl"), do: "Betl"
  defp game_label("sans"), do: "Sans"
  defp game_label(other), do: other

  defp defense_label("dodjem"), do: "Dodjem (Follow)"
  defp defense_label("ne_dodjem"), do: "Ne dodjem (Pass)"
  defp defense_label("poziv"), do: "Poziv (Call partner)"
  defp defense_label(other), do: other

  defp kontra_label("kontra"), do: "Kontra!"
  defp kontra_label("moze"), do: "Može (Accept)"
  defp kontra_label(other), do: other
end
```

## Step 5: CSS Styling

Create or update `assets/css/game.css`

Traditional card table feel. Green felt background. Cards look like real
playing cards.

```css
/* Card table */
.game-table {
  background: #1a5c2a;  /* Green felt */
  background-image: radial-gradient(ellipse at center, #1e6b31 0%, #143d1f 100%);
  min-height: 100vh;
  display: grid;
  grid-template-rows: auto 1fr auto auto;
  grid-template-columns: auto 1fr auto;
  padding: 1rem;
  gap: 1rem;
  position: relative;
}

/* Playing cards */
.card {
  width: 60px;
  height: 90px;
  background: white;
  border-radius: 6px;
  border: 1px solid #ccc;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  font-size: 1.2rem;
  font-weight: bold;
  cursor: default;
  transition: transform 0.15s, box-shadow 0.15s;
  box-shadow: 0 2px 4px rgba(0,0,0,0.3);
}

.card.red { color: #cc0000; }
.card.black { color: #111; }

.card.playable {
  cursor: pointer;
  border: 2px solid #ffd700;
}

.card.playable:hover {
  transform: translateY(-10px);
  box-shadow: 0 8px 16px rgba(0,0,0,0.4);
}

.card.selected {
  transform: translateY(-15px);
  border: 2px solid #00ff00;
  box-shadow: 0 0 12px rgba(0,255,0,0.5);
}

.card-back {
  background: linear-gradient(135deg, #1a237e 0%, #283593 50%, #1a237e 100%);
  border: 2px solid #0d1547;
}

.card-back .card-pattern {
  width: 80%;
  height: 80%;
  border: 1px solid rgba(255,255,255,0.2);
  border-radius: 3px;
}

/* Hands */
.hand {
  display: flex;
  justify-content: center;
  gap: -20px;  /* Overlapping cards */
}

.hand .card {
  margin-left: -15px;
}

.hand .card:first-child {
  margin-left: 0;
}

.opponent-hand {
  display: flex;
  justify-content: center;
}

.opponent-top { grid-row: 1; grid-column: 2; }
.opponent-left { grid-row: 2; grid-column: 1; flex-direction: column; }

.opponent-hand .card-back {
  width: 40px;
  height: 60px;
  margin-left: -10px;
}

/* Table center */
.table-center {
  grid-row: 2;
  grid-column: 2;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
}

.trick-area {
  position: relative;
  width: 200px;
  height: 200px;
}

.trick-card {
  position: absolute;
}

.trick-seat-0 { bottom: 0; left: 50%; transform: translateX(-50%); }
.trick-seat-1 { left: 0; top: 50%; transform: translateY(-50%); }
.trick-seat-2 { top: 0; left: 50%; transform: translateX(-50%); }

/* Talon */
.talon {
  display: flex;
  gap: 8px;
  margin: 1rem 0;
}

/* Info panel */
.info-panel {
  grid-row: 2;
  grid-column: 3;
  background: rgba(0,0,0,0.3);
  border-radius: 8px;
  padding: 1rem;
  color: #e0e0e0;
  font-family: 'Georgia', serif;
  min-width: 180px;
}

/* Player hand area */
.player-hand {
  grid-row: 3;
  grid-column: 1 / -1;
  display: flex;
  justify-content: center;
  padding: 1rem 0;
}

/* Action bar */
.action-bar {
  grid-row: 4;
  grid-column: 1 / -1;
  display: flex;
  justify-content: center;
  padding: 0.5rem;
}

.actions {
  display: flex;
  gap: 0.5rem;
  flex-wrap: wrap;
  justify-content: center;
}

.actions button {
  padding: 0.5rem 1.2rem;
  border-radius: 6px;
  border: none;
  font-size: 1rem;
  cursor: pointer;
  transition: background 0.15s;
}

.btn-primary {
  background: #2196F3;
  color: white;
}

.btn-bid {
  background: #4CAF50;
  color: white;
}

.btn-bid:hover { background: #388E3C; }

.btn-declare { background: #FF9800; color: white; }
.btn-defense { background: #9C27B0; color: white; }
.btn-kontra { background: #F44336; color: white; }

.btn-bid[disabled], 
button[disabled] {
  opacity: 0.5;
  cursor: not-allowed;
}

/* Event feed */
.event-feed {
  position: absolute;
  top: 1rem;
  right: 1rem;
  max-width: 250px;
}

.event-item {
  background: rgba(0,0,0,0.7);
  color: #fff;
  padding: 0.3rem 0.6rem;
  border-radius: 4px;
  margin-bottom: 0.3rem;
  font-size: 0.85rem;
  animation: fadeIn 0.3s ease-in;
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateX(20px); }
  to { opacity: 1; transform: translateX(0); }
}

/* Waiting indicator */
.waiting {
  color: #ffd700;
  font-style: italic;
  animation: pulse 1.5s infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 0.6; }
  50% { opacity: 1; }
}

/* Error toast */
.error-toast {
  position: fixed;
  bottom: 2rem;
  left: 50%;
  transform: translateX(-50%);
  background: #F44336;
  color: white;
  padding: 0.8rem 1.5rem;
  border-radius: 8px;
  animation: fadeIn 0.3s ease-in;
}

/* Scoring display - traditional three-column format */
.score-sheet {
  font-family: 'Courier New', monospace;
  font-size: 0.8rem;
}

.hint {
  color: #aaa;
  font-style: italic;
}
```

## Step 6: Router

Add the game route:

```elixir
# lib/preferans_web/router.ex
scope "/", PreferansWeb do
  pipe_through :browser

  live "/", PageLive, :index
  live "/play", GameLive, :play
end
```

## Step 7: Configuration

Add to `config/config.exs`:

```elixir
config :preferans_web,
  server_path: System.get_env("PREFERANS_SERVER") || "./priv/bin/preferans_server",
  model_dir: System.get_env("PREFERANS_MODELS") || "./priv/models/"
```

## Testing Without the C++ Server

For development, create a mock server in Elixir that responds to the
same JSON protocol. This lets you build and test the UI without the 
C++ binary:

Create `lib/preferans_web/game/mock_server.ex` — a GenServer that 
simulates the game protocol with random responses. Cards are dealt 
randomly, AI "thinks" for 500ms then plays randomly.

## Implementation Order

1. GameServer GenServer with Port communication
2. Mock server for development
3. GameLive with basic layout
4. Card components (face up, face down, clickable)
5. Action bar (bid buttons, discard confirm, declare game)
6. CSS styling (green felt, card appearance)
7. Wire up real C++ server
8. Scoring display
9. Event animations (AI plays cards with delay)
10. Language toggle (Serbian/English)

## Design Direction

Traditional card table feel. Green felt background. Cards should look 
like real playing cards — white with suit symbols, red for hearts/diamonds,
black for spades/clubs. Clean, not flashy. 

The scoring sheet should match the traditional paper format: three columns 
with bule in center, supe on sides, kapa line, refe marks.

Serbian terminology as default: Dalje, Moje, Dodjem, Kontra, Betl, Sans.
English translations in parentheses or via a toggle.
