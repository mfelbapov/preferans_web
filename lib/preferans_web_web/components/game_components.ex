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
        <span :if={@is_declarer} class="text-amber-300 text-xs">(D)</span>
      </div>
      <div class="flex gap-0.5">
        <.card :for={_ <- 1..min(@card_count, 10)} face={:down} size={:small} />
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
    <div class="relative w-[220px] h-[160px]">
      <div
        :for={entry <- @current_trick}
        class={trick_card_position(entry.player, @my_seat, @positions)}
      >
        <.card card={entry.card} size={:small} />
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
          phx-click="bid"
          phx-value-action="bid"
          phx-value-value={v}
          class="btn-game btn-game-primary"
        >
          {bid_label(v)}
        </button>
      </div>
    </div>
    """
  end

  defp bid_buttons(legal_actions) do
    Enum.filter(legal_actions, &match?({:bid, _}, &1))
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
            card={c}
            clickable={true}
            selected={MapSet.member?(@selected, c)}
            click_event="toggle_discard"
            click_value={Cards.card_to_key(c)}
          />
        </div>
        <div class="mt-3 text-center">
          <button
            phx-click="confirm_discard"
            disabled={MapSet.size(@selected) != 2}
            class={[
              "btn-game",
              MapSet.size(@selected) == 2 && "btn-game-primary",
              MapSet.size(@selected) != 2 && "btn-game-disabled"
            ]}
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
            :for={game <- @view.legal_actions}
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
        <button phx-click="defense" phx-value-action="dodjem" class="btn-game btn-game-primary">
          {gettext("I defend")}
        </button>
        <button phx-click="defense" phx-value-action="ne_dodjem" class="btn-game btn-game-secondary">
          {gettext("I pass")}
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

  ## Trick play phase

  attr :view, :map, required: true
  attr :positions, :map, required: true

  def trick_play_phase(assigns) do
    playable = playable_cards(assigns.view.legal_actions)
    assigns = assign(assigns, :playable, playable)

    ~H"""
    <div class="flex flex-col items-center gap-4">
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
        card={c}
        clickable={MapSet.member?(@playable, c)}
        dimmed={@phase_clickable and @view.is_my_turn and not MapSet.member?(@playable, c)}
        click_event={if MapSet.member?(@playable, c), do: "play_card"}
        click_value={if MapSet.member?(@playable, c), do: Cards.card_to_key(c)}
      />
    </div>
    """
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

  defp refe_filled(count) when count > 0, do: 1..count
  defp refe_filled(_), do: []

  defp refe_empty(count) when count < 2, do: 1..(2 - count)
  defp refe_empty(_), do: []
end
