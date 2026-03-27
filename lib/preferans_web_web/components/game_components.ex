defmodule PreferansWebWeb.GameComponents do
  @moduledoc """
  Phase-specific components and scoring sidebar for the game table.
  """
  use Phoenix.Component
  use Gettext, backend: PreferansWebWeb.Gettext

  import PreferansWebWeb.CardComponent

  alias PreferansWeb.Game.Cards

  ## Player areas

  attr :name, :string, required: true
  attr :card_count, :integer, required: true
  attr :tricks, :integer, default: 0
  attr :is_current, :boolean, default: false
  attr :is_declarer, :boolean, default: false
  attr :is_dealer, :boolean, default: false
  attr :position, :atom, required: true, doc: ":left or :right"

  def opponent_area(assigns) do
    ~H"""
    <div class={[
      "flex flex-col items-center gap-1 p-2",
      @position == :left && "self-start",
      @position == :right && "self-end"
    ]}>
      <div class="flex items-center gap-1.5 text-sm text-green-100">
        <span class={[
          "w-2 h-2 rounded-full",
          @is_current && "bg-amber-400",
          !@is_current && "bg-transparent"
        ]} />
        <span class="font-medium">{@name}</span>
        <span :if={@is_dealer} class="text-green-400/70 text-2xl">{gettext("Ⓓ")}</span>
        <span
          :if={@is_declarer}
          class="bg-red-600 text-white text-xs font-bold uppercase px-1.5 py-0.5 rounded"
        >
          {gettext("IGRAC")}
        </span>
      </div>
      <div class="flex gap-0.5">
        <.card :for={_ <- 1..min(@card_count, 10)//1} face={:down} size={:small} />
      </div>
      <div class="text-xs text-green-200/70">
        {gettext("Tricks: %{count}", count: @tricks)}
      </div>
    </div>
    """
  end

  ## Trick area

  attr :current_trick, :list, default: []
  attr :my_seat, :integer, required: true
  attr :positions, :map, required: true

  def trick_area(assigns) do
    ~H"""
    <div class="relative w-[280px] h-[180px]">
      <div
        :for={entry <- @current_trick}
        class={trick_card_position(entry.player, @my_seat, @positions)}
      >
        <.card id={"trick-#{card_dom_id(entry.card)}"} card={entry.card} size={:small} />
      </div>
    </div>
    """
  end

  defp trick_card_position(player, my_seat, positions) do
    base = "absolute"

    cond do
      player == my_seat -> "#{base} bottom-0 left-1/2 -translate-x-1/2"
      player == positions.left -> "#{base} top-0 left-4"
      player == positions.right -> "#{base} top-0 right-4"
      true -> base
    end
  end

  ## Bidding phase

  attr :view, :map, required: true

  def bidding_phase(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-4">
      <div class="bg-green-900/50 rounded-lg p-3 max-w-xs w-full">
        <h3 class="text-green-100 text-sm font-semibold mb-2">{gettext("Bidding")}</h3>
        <div class="space-y-1 max-h-32 overflow-y-auto">
          <div :for={entry <- @view.bid_history} class="text-sm text-green-200/80">
            <span class="font-medium">{display_name(@view, entry.player)}:</span>
            <span>{format_bid_action(entry.action)}</span>
          </div>
        </div>
        <div :if={@view.is_my_turn} class="text-amber-300 text-sm mt-2 font-medium">
          {gettext("Your turn to bid")}
        </div>
        <div :if={!@view.is_my_turn} class="text-green-300/60 text-sm mt-2">
          {gettext("Waiting for %{name}...", name: display_name(@view, @view.current_player))}
        </div>
      </div>

      <div :if={@view.is_my_turn} class="flex flex-wrap gap-2 justify-center">
        <button
          phx-click="bid"
          phx-value-action="dalje"
          class="btn-game btn-game-secondary"
        >
          {gettext("Pass")}
        </button>
        <button
          :for={{:bid, v} <- bid_buttons(@view.legal_actions)}
          phx-click="bid_value"
          phx-value-bid={to_string(v)}
          class="btn-game btn-game-primary"
        >
          {bid_label(v)}
        </button>
        <button
          :if={:moje in @view.legal_actions}
          phx-click="bid_moje"
          class="btn-game btn-game-accent"
        >
          {gettext("Moje")}
        </button>
        <button
          :if={:igra in @view.legal_actions}
          phx-click="bid_igra"
          phx-value-action="igra"
          class="btn-game btn-game-accent"
        >
          {gettext("Igra")}
        </button>
        <button
          :if={:igra_betl in @view.legal_actions}
          phx-click="bid_igra"
          phx-value-action="igra_betl"
          class="btn-game btn-game-accent"
        >
          {gettext("Igra Betl")}
        </button>
        <button
          :if={:igra_sans in @view.legal_actions}
          phx-click="bid_igra"
          phx-value-action="igra_sans"
          class="btn-game btn-game-accent"
        >
          {gettext("Igra Sans")}
        </button>
      </div>
    </div>
    """
  end

  defp bid_buttons(legal_actions) do
    case Enum.filter(legal_actions, &match?({:bid, _}, &1)) do
      [] -> []
      bids -> [Enum.min_by(bids, fn {:bid, v} -> v end)]
    end
  end

  defp bid_label(value) do
    names = %{
      2 => "2 (Pik)",
      3 => "3 (Karo)",
      4 => "4 (Herc)",
      5 => "5 (Tref)",
      6 => "6 (Betl)",
      7 => "7 (Sans)"
    }

    Map.get(names, value, to_string(value))
  end

  defp format_bid_action(:dalje), do: gettext("Pass")
  defp format_bid_action({:bid, v}), do: bid_label(v)
  defp format_bid_action({:moje, v}), do: "#{gettext("Moje")} (#{bid_label(v)})"
  defp format_bid_action(:moje), do: gettext("Moje")
  defp format_bid_action(:igra), do: gettext("Igra")
  defp format_bid_action(:igra_betl), do: gettext("Igra Betl")
  defp format_bid_action(:igra_sans), do: gettext("Igra Sans")

  ## Discard phase

  attr :view, :map, required: true
  attr :selected, :any, required: true, doc: "MapSet of selected cards"

  def discard_phase(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-4">
      <div :if={@view.my_seat == @view.declarer}>
        <p class="text-green-100 text-sm mb-2 text-center">
          {gettext("Choose 2 cards to discard")}
        </p>
        <div class="flex flex-wrap gap-1 justify-center">
          <.card
            :for={c <- @view.my_hand}
            id={"discard-#{card_dom_id(c)}"}
            card={c}
            clickable={true}
            selected={MapSet.member?(@selected, c)}
            click_event="toggle_discard"
            click_value={Cards.card_to_key(c)}
          />
        </div>
        <div class="mt-3 text-center">
          <button
            :if={MapSet.size(@selected) == 2}
            phx-click="confirm_discard"
            class="btn-game btn-game-primary"
            id="confirm-discard-btn"
          >
            {gettext("Discard")}
          </button>
          <button
            :if={MapSet.size(@selected) != 2}
            class="btn-game btn-game-disabled"
            disabled
          >
            {gettext("Discard")}
          </button>
        </div>
      </div>
      <div :if={@view.my_seat != @view.declarer} class="text-green-200/60 text-sm">
        {gettext("Waiting for %{name}...", name: display_name(@view, @view.declarer))}
      </div>
    </div>
    """
  end

  ## Declare game phase

  attr :view, :map, required: true

  def declare_game_phase(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-4">
      <div :if={@view.is_my_turn}>
        <p class="text-green-100 text-sm mb-3 text-center">{gettext("Choose your game")}</p>
        <div class="flex flex-wrap gap-2 justify-center">
          <button
            :for={{:declare, game} <- @view.legal_actions}
            phx-click="declare_game"
            phx-value-game={game}
            class="btn-game btn-game-primary"
          >
            {Cards.game_name(game)} {game_suit_symbol(game)}
          </button>
        </div>
      </div>
      <div :if={!@view.is_my_turn} class="text-green-200/60 text-sm">
        {gettext("Waiting for %{name}...", name: display_name(@view, @view.current_player))}
      </div>
    </div>
    """
  end

  defp game_suit_symbol(game) when game in [:pik, :karo, :herc, :tref],
    do: Cards.suit_symbol(game)

  defp game_suit_symbol(_), do: ""

  ## Defense phase

  attr :view, :map, required: true

  def defense_phase(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-4">
      <div class="bg-green-900/50 rounded-lg p-3 text-center">
        <p class="text-green-100 text-sm">
          {gettext("%{name} plays %{game}",
            name: display_name(@view, @view.declarer),
            game: "#{Cards.game_name(@view.game_type)} #{game_suit_symbol(@view.game_type)}"
          )}
        </p>
        <div :for={{seat, response} <- @view.defense_responses} class="text-sm text-green-200/70 mt-1">
          {display_name(@view, seat)}: {format_defense(response)}
        </div>
      </div>

      <div :if={@view.is_my_turn} class="flex gap-3">
        <button
          :if={:dodjem in @view.legal_actions}
          phx-click="defense"
          phx-value-action="dodjem"
          class="btn-game btn-game-primary"
        >
          {gettext("I defend")}
        </button>
        <button
          :if={:ne_dodjem in @view.legal_actions}
          phx-click="defense"
          phx-value-action="ne_dodjem"
          class="btn-game btn-game-secondary"
        >
          {gettext("I pass")}
        </button>
        <button
          :if={:sam in @view.legal_actions}
          phx-click="defense"
          phx-value-action="sam"
          class="btn-game btn-game-primary"
        >
          {gettext("Play alone")}
        </button>
        <button
          :if={:idemo_zajedno in @view.legal_actions}
          phx-click="defense"
          phx-value-action="idemo_zajedno"
          class="btn-game btn-game-accent"
        >
          {gettext("Call partner")}
        </button>
      </div>
      <div
        :if={!@view.is_my_turn and map_size(@view.defense_responses) < 2}
        class="text-green-200/60 text-sm"
      >
        {gettext("Waiting for %{name}...", name: display_name(@view, @view.current_player))}
      </div>
    </div>
    """
  end

  defp format_defense(:dodjem), do: gettext("I defend")
  defp format_defense(:ne_dodjem), do: gettext("I pass")
  defp format_defense(:poziv), do: gettext("Called partner")
  defp format_defense(:sam), do: gettext("Alone")
  defp format_defense(:idemo_zajedno), do: gettext("Called partner")

  ## Kontra phase

  attr :view, :map, required: true

  def kontra_phase(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-4">
      <div class="bg-green-900/50 rounded-lg p-3 text-center">
        <p class="text-green-100 text-sm">
          {gettext("%{name} plays %{game}",
            name: display_name(@view, @view.declarer),
            game: "#{Cards.game_name(@view.game_type)} #{game_suit_symbol(@view.game_type)}"
          )}
        </p>
        <p :if={@view.kontra_level > 0} class="text-amber-300 text-sm font-bold mt-1">
          {kontra_level_label(@view.kontra_level)}
        </p>
      </div>

      <div :if={@view.is_my_turn} class="flex gap-3">
        <button
          :for={action <- kontra_actions(@view.legal_actions)}
          phx-click="kontra"
          phx-value-action={action}
          class={kontra_button_class(action)}
        >
          {kontra_action_label(action)}
        </button>
      </div>
      <div :if={!@view.is_my_turn} class="text-green-200/60 text-sm">
        {gettext("Waiting for %{name}...", name: display_name(@view, @view.current_player))}
      </div>
    </div>
    """
  end

  defp kontra_actions(legal_actions) do
    Enum.map(legal_actions, fn
      :kontra -> "kontra"
      :rekontra -> "rekontra"
      :subkontra -> "subkontra"
      :mortkontra -> "mortkontra"
      :moze -> "moze"
      _ -> nil
    end)
    |> Enum.filter(& &1)
  end

  defp kontra_action_label("kontra"), do: gettext("Kontra!")
  defp kontra_action_label("rekontra"), do: gettext("Rekontra!")
  defp kontra_action_label("subkontra"), do: gettext("Subkontra!")
  defp kontra_action_label("mortkontra"), do: gettext("Mortkontra!")
  defp kontra_action_label("moze"), do: gettext("Accept")

  defp kontra_button_class("moze"), do: "btn-game btn-game-secondary"
  defp kontra_button_class(_), do: "btn-game btn-game-accent"

  defp kontra_level_label(1), do: gettext("Kontra")
  defp kontra_level_label(2), do: gettext("Rekontra")
  defp kontra_level_label(3), do: gettext("Subkontra")
  defp kontra_level_label(4), do: gettext("Mortkontra")
  defp kontra_level_label(_), do: ""

  ## Game info bar (shown during trick play and trick result)

  attr :view, :map, required: true

  def game_info_bar(assigns) do
    caller = find_caller(assigns.view.defense_responses)
    assigns = assign(assigns, :caller, caller)

    ~H"""
    <div
      :if={@view.game_type}
      class="flex flex-col items-center gap-1"
    >
      <div class="flex items-center gap-2 text-xs text-green-200/70 bg-green-900/40 rounded px-3 py-1">
        <span class="font-semibold text-green-100">
          {Cards.game_name(@view.game_type)} {game_suit_symbol(@view.game_type)}
        </span>
        <span>—</span>
        <span>{display_name(@view, @view.declarer)} {gettext("declares")}</span>
      </div>
      <div
        :if={@caller}
        class="text-xs text-amber-300/80 bg-amber-900/30 rounded px-3 py-1"
      >
        {gettext("%{name} called you back (Poziv)",
          name: display_name(@view, @caller)
        )}
      </div>
    </div>
    """
  end

  defp find_caller(defense_responses) do
    Enum.find_value(defense_responses, fn
      {player, :poziv} -> player
      {player, :idemo_zajedno} -> player
      _ -> nil
    end)
  end

  ## Trick play phase

  attr :view, :map, required: true
  attr :positions, :map, required: true

  def trick_play_phase(assigns) do
    playable = playable_cards(assigns.view.legal_actions)
    assigns = assign(assigns, :playable, playable)

    ~H"""
    <div class="flex flex-col items-center gap-4">
      <.game_info_bar view={@view} />
      <.trick_area
        current_trick={@view.current_trick}
        my_seat={@view.my_seat}
        positions={@positions}
      />

      <div :if={@view.is_my_turn} class="text-amber-300 text-sm font-medium">
        {gettext("Your turn to play")}
      </div>
      <div :if={!@view.is_my_turn} class="text-green-200/60 text-sm">
        {gettext("Waiting for %{name} to play...", name: display_name(@view, @view.current_player))}
      </div>
    </div>
    """
  end

  ## Trick result phase (pause after each trick)

  attr :view, :map, required: true
  attr :positions, :map, required: true

  def trick_result_phase(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-4">
      <.game_info_bar view={@view} />
      <.trick_area
        current_trick={@view.current_trick}
        my_seat={@view.my_seat}
        positions={@positions}
      />

      <div class="text-center">
        <div class="text-green-100 text-sm mb-2">
          {display_name(@view, @view.trick_winner)} {gettext("wins the trick")}
        </div>
        <div class="grid grid-cols-3 gap-4 text-center text-xs text-green-200/70 mb-3">
          <div :for={seat <- [0, 1, 2]}>
            <span class="font-medium">{display_name(@view, seat)}</span>: {Enum.at(
              @view.tricks_won,
              seat
            )}
          </div>
        </div>
        <button phx-click="next_trick" class="btn-game btn-game-primary" id="next-trick-btn">
          {gettext("Next")} →
        </button>
      </div>
    </div>
    """
  end

  ## Scoring phase

  attr :view, :map, required: true

  def scoring_phase(assigns) do
    ~H"""
    <div class="bg-green-900/80 rounded-xl p-5 max-w-sm mx-auto border border-green-700/50 shadow-xl">
      <h3 class="text-green-100 font-bold text-lg mb-3 text-center">{gettext("Hand Result")}</h3>

      <div :if={@view.scoring_result} class="space-y-3">
        <div :if={@view.scoring_result.all_passed} class="text-center text-green-200">
          {gettext("All passed — Refe")}
        </div>

        <div :if={!@view.scoring_result.all_passed}>
          <div class="text-center text-green-100 mb-2">
            {display_name(@view, @view.declarer)}: {Cards.game_name(@view.game_type)} — {if @view.scoring_result.declarer_passed,
              do: gettext("Passed"),
              else: gettext("Failed")}
            {if @view.scoring_result.declarer_passed, do: "✓", else: "✗"}
          </div>

          <div class="grid grid-cols-3 gap-2 text-center text-sm">
            <div :for={seat <- [0, 1, 2]} class="text-green-200/80">
              <div class="font-medium">{display_name(@view, seat)}</div>
              <div>
                {gettext("Tricks: %{count}", count: Enum.at(@view.scoring_result.tricks, seat))}
              </div>
              <div class={bule_change_class(Enum.at(@view.scoring_result.bule_changes, seat))}>
                {format_bule_change(Enum.at(@view.scoring_result.bule_changes, seat))}
              </div>
            </div>
          </div>
        </div>

        <div class="text-center mt-4">
          <button phx-click="next_hand" class="btn-game btn-game-primary" id="next-hand-btn">
            {gettext("Next Hand")} →
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp bule_change_class(change) when change < 0, do: "text-green-300 font-bold"
  defp bule_change_class(change) when change > 0, do: "text-red-400 font-bold"
  defp bule_change_class(_), do: "text-green-200/60"

  defp format_bule_change(0), do: "±0"
  defp format_bule_change(n) when n > 0, do: "+#{n}"
  defp format_bule_change(n), do: to_string(n)

  ## Hand over phase (brief, auto-transitions)

  attr :view, :map, required: true

  def hand_over_phase(assigns) do
    ~H"""
    <div class="text-center text-green-200/80 text-sm">
      {gettext("Dealing next hand...")}
    </div>
    """
  end

  ## Scoring sidebar

  attr :view, :map, required: true

  def scoring_sidebar(assigns) do
    ~H"""
    <div class="w-72 bg-sidebar-bg border-l border-green-900/50 p-3 flex flex-col gap-3 overflow-y-auto">
      <h3 class="text-green-100 font-bold text-sm text-center border-b border-green-800/50 pb-2">
        {gettext("Scoring Sheet")}
      </h3>

      <div class="grid grid-cols-3 gap-1 text-center text-xs">
        <div :for={seat <- [0, 1, 2]} class="space-y-1">
          <div class={[
            "font-bold text-sm",
            seat == @view.my_seat && "text-amber-300",
            seat != @view.my_seat && "text-green-200"
          ]}>
            {display_name(@view, seat)}
          </div>
        </div>
      </div>

      <%!-- Bule --%>
      <div class="bg-green-950/50 rounded p-2">
        <div class="text-green-300/70 text-xs text-center mb-1">{gettext("Bule")}</div>
        <div class="grid grid-cols-3 gap-1 text-center font-mono text-sm">
          <div :for={seat <- [0, 1, 2]} class="text-green-100">
            {Enum.at(@view.match_bule, seat)}
          </div>
        </div>
      </div>

      <%!-- Supe --%>
      <div :if={map_size(@view.match_supe_ledger) > 0} class="bg-green-950/50 rounded p-2">
        <div class="text-green-300/70 text-xs text-center mb-1">{gettext("Supe")}</div>
        <div class="space-y-0.5 text-xs text-green-200/70">
          <div :for={{{from, to}, amount} <- @view.match_supe_ledger}>
            {display_name(@view, to)}: {amount} vs {display_name(@view, from)}
          </div>
        </div>
      </div>

      <%!-- Refes --%>
      <div class="bg-green-950/50 rounded p-2">
        <div class="text-green-300/70 text-xs text-center mb-1">{gettext("Refes")}</div>
        <div class="grid grid-cols-3 gap-1 text-center text-sm">
          <div :for={seat <- [0, 1, 2]} class="text-green-200/80 flex justify-center gap-0.5">
            <span
              :for={_ <- refe_filled(Enum.at(@view.match_refe_counts, seat))}
              class="text-amber-400"
            >
              ▮
            </span>
            <span
              :for={_ <- refe_empty(Enum.at(@view.match_refe_counts, seat))}
              class="text-green-700"
            >
              ▯
            </span>
          </div>
        </div>
      </div>

      <%!-- Info --%>
      <div class="text-xs text-green-300/50 text-center mt-auto space-y-0.5">
        <div>{gettext("Hand #%{number}", number: @view.hands_played + 1)}</div>
        <div>{gettext("Dealer: %{name}", name: display_name(@view, @view.dealer))}</div>
      </div>
    </div>
    """
  end

  ## My hand display (used by trick play and other phases)

  attr :view, :map, required: true
  attr :phase_clickable, :boolean, default: false

  def my_hand(assigns) do
    playable =
      if assigns.phase_clickable and assigns.view.is_my_turn do
        playable_cards(assigns.view.legal_actions)
      else
        MapSet.new()
      end

    assigns = assign(assigns, :playable, playable)

    ~H"""
    <div class="flex flex-wrap gap-1 justify-center">
      <.card
        :for={c <- @view.my_hand}
        id={"hand-#{card_dom_id(c)}"}
        card={c}
        clickable={MapSet.member?(@playable, c)}
        dimmed={@phase_clickable and @view.is_my_turn and not MapSet.member?(@playable, c)}
        click_event={if MapSet.member?(@playable, c), do: "play_card"}
        click_value={if MapSet.member?(@playable, c), do: Cards.card_to_key(c)}
      />
    </div>
    """
  end

  ## Debug panel

  attr :debug_state, :map, required: true

  def debug_panel(assigns) do
    text = format_debug_text(assigns.debug_state)
    assigns = assign(assigns, :text, text)

    ~H"""
    <div class="w-96 bg-gray-900 border-l border-gray-700 p-3 flex flex-col gap-2 overflow-y-auto">
      <div class="flex justify-between items-center border-b border-gray-700 pb-2">
        <h3 class="text-gray-100 font-bold text-sm">Debug State</h3>
        <button
          id="copy-debug-btn"
          phx-hook="CopyToClipboard"
          data-target="debug-pre"
          class="text-xs bg-gray-700 hover:bg-gray-600 text-gray-200 px-2 py-1 rounded"
        >
          Copy All
        </button>
      </div>
      <pre id="debug-pre" class="text-xs text-gray-300 font-mono whitespace-pre-wrap break-words">{@text}</pre>
    </div>
    """
  end

  defp format_debug_text(d) do
    cpp = d.cpp_state
    trick_play = cpp["trick_play"]

    sections = [
      "=== GAME DEBUG STATE ===",
      "Phase: #{cpp["phase"]}",
      "Current Player: #{cpp["current_player"]}",
      "Dealer: #{d.current_dealer}",
      "Declarer: #{cpp["declarer"]}",
      "Game Type: #{cpp["declared_game"]}",
      "Game Value: #{cpp["game_value"]}",
      "Is Igra: #{cpp["is_igra"]}",
      "Kontra Level: #{cpp["kontra_level"]}",
      "Kontra Giver: #{cpp["kontra_giver"]}",
      "",
      "=== PLAYERS ===",
      format_players(d.players),
      "",
      "=== MY SEAT: #{d.seat} ===",
      "",
      "=== HAND ===",
      inspect(cpp["hand"]),
      "",
      "=== TALON ===",
      inspect(cpp["talon"]),
      "",
      "=== LEGAL ACTIONS ===",
      inspect(cpp["legal_actions"]),
      "",
      "=== BID HISTORY ===",
      format_bid_history(d.bid_history),
      "",
      "=== DEFENSE RESPONSES ===",
      format_defense_responses(d.defense_responses),
      "Defenders: #{inspect(d.defenders)}",
      "",
      "=== TRICK STATE ===",
      format_trick_state(trick_play),
      "",
      "=== ALL EVENTS ===",
      format_events(d.all_events),
      "",
      "=== MATCH STATE ===",
      "Bule: #{inspect(d.match_bule)}",
      "Refes: #{inspect(d.match_refe_counts)}",
      "Supe Ledger: #{inspect(d.match_supe_ledger)}",
      "Hands Played: #{d.hands_played}",
      "Max Refes: #{d.max_refes}",
      "",
      "=== SCORING RESULT ===",
      inspect(cpp["result"]),
      "",
      "=== RAW CPP STATE ===",
      inspect(cpp, pretty: true, limit: :infinity)
    ]

    Enum.join(sections, "\n")
  end

  defp format_players(players) do
    Enum.map_join(players, "\n", fn p ->
      "Seat #{p.seat}: #{p.display_name}#{if p.is_ai, do: " (AI)", else: " (Human)"}"
    end)
  end

  defp format_bid_history(history) do
    Enum.map_join(history, "\n", fn entry ->
      "Seat #{entry.player}: #{inspect(entry.action)}"
    end)
  end

  defp format_defense_responses(responses) do
    Enum.map_join(responses, "\n", fn {seat, action} ->
      "Seat #{seat}: #{inspect(action)}"
    end)
  end

  defp format_trick_state(nil), do: "No trick play state"

  defp format_trick_state(tp) do
    [
      "Trick Number: #{tp["trick_number"]}",
      "Tricks Won: #{inspect(tp["tricks_won"])}",
      "Current Trick: #{inspect(tp["current_trick"])}"
    ]
    |> Enum.join("\n")
  end

  defp format_events(events) do
    Enum.map_join(events, "\n", fn event ->
      inspect(event)
    end)
  end

  ## Helpers

  defp display_name(view, seat) do
    Map.get(view.display_names, seat, "Seat #{seat}")
  end

  defp playable_cards(legal_actions) do
    legal_actions
    |> Enum.filter(&match?({:play, _}, &1))
    |> Enum.map(fn {:play, card} -> card end)
    |> MapSet.new()
  end

  defp card_dom_id({suit, rank}), do: "#{suit}-#{rank}"

  defp refe_filled(count) when count > 0, do: 1..count
  defp refe_filled(_), do: []

  defp refe_empty(count) when count < 2, do: 1..(2 - count)
  defp refe_empty(_), do: []
end
