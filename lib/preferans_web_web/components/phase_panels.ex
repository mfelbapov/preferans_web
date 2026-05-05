defmodule PreferansWebWeb.PhasePanels do
  @moduledoc """
  Phase-specific center-panel components: bidding, discard, declare, defense,
  kontra, trick area, scoring. Visual port of `phase-panels.jsx`, driven by the
  `view` map produced by `PreferansWeb.Game.GameServer.get_player_view/2`.

  All `phx-click` event names match the handlers already in
  `PreferansWebWeb.GameLive`.
  """
  use Phoenix.Component
  use Gettext, backend: PreferansWebWeb.Gettext

  import PreferansWebWeb.CardComponent

  alias PreferansWeb.Game.Cards

  ## ----------------------------------------------------------------- Phase banner

  attr :phase, :atom, required: true
  attr :lang, :atom, default: :sr

  def phase_banner(assigns) do
    ~H"""
    <div style="font-family: var(--font-display); font-size: 11px; letter-spacing: 0.3em; color: #d4b57299; text-align: center; text-transform: uppercase; padding: 6px 0;">
      {phase_label(@phase, @lang)}
    </div>
    """
  end

  defp phase_label(:bid, :sr), do: "LICITACIJA"
  defp phase_label(:bid, _), do: "BIDDING"
  defp phase_label(:discard, :sr), do: "BACANJE"
  defp phase_label(:discard, _), do: "DISCARD"
  defp phase_label(:declare_game, :sr), do: "NAJAVA"
  defp phase_label(:declare_game, _), do: "DECLARE"
  defp phase_label(:defense, :sr), do: "IGRA / NE"
  defp phase_label(:defense, _), do: "DEFENSE"
  defp phase_label(:kontra, :sr), do: "KONTRA"
  defp phase_label(:kontra, _), do: "KONTRA"
  defp phase_label(:trick_play, :sr), do: "IGRA"
  defp phase_label(:trick_play, _), do: "TRICK PLAY"
  defp phase_label(:hand_over, :sr), do: "OBRAČUN"
  defp phase_label(:hand_over, _), do: "SCORING"
  defp phase_label(_, _), do: ""

  ## ----------------------------------------------------------------- Bidding

  @bid_ladder [
    %{value: 2, sr: "Pik", en: "Pik", suit: :pik},
    %{value: 3, sr: "Karo", en: "Karo", suit: :karo},
    %{value: 4, sr: "Herc", en: "Herc", suit: :herc},
    %{value: 5, sr: "Tref", en: "Tref", suit: :tref},
    %{value: 6, sr: "Betl", en: "Betl", suit: nil},
    %{value: 7, sr: "Sans", en: "Sans", suit: nil}
  ]

  attr :view, :map, required: true
  attr :lang, :atom, default: :sr

  def bidding_panel(assigns) do
    legal_bid_values =
      assigns.view.legal_actions
      |> Enum.filter(&match?({:bid, _}, &1))
      |> Enum.map(fn {:bid, v} -> v end)
      |> MapSet.new()

    assigns =
      assigns
      |> assign(:legal_bid_values, legal_bid_values)
      |> assign(:bid_ladder, @bid_ladder)
      |> assign(:can_pass?, :dalje in assigns.view.legal_actions)
      |> assign(:can_moje?, :moje in assigns.view.legal_actions)
      |> assign(:can_igra?, :igra in assigns.view.legal_actions)
      |> assign(:can_igra_betl?, :igra_betl in assigns.view.legal_actions)
      |> assign(:can_igra_sans?, :igra_sans in assigns.view.legal_actions)

    ~H"""
    <div style="display: flex; flex-direction: column; gap: 12px; align-items: center; min-width: 420px;">
      <.phase_banner phase={:bid} lang={@lang} />

      <div style="display: flex; gap: 6px; flex-wrap: wrap; justify-content: center; min-height: 32px; max-width: 420px;">
        <div
          :if={@view.bid_history == []}
          style="color: #d4b57266; font-family: var(--font-mono); font-size: 11px; letter-spacing: 0.15em;"
        >
          {if @lang == :sr, do: "na potezu…", else: "awaiting bid…"}
        </div>
        <div
          :for={entry <- @view.bid_history}
          style={bid_chip_style(entry.action)}
        >
          <span style="opacity: 0.7; margin-right: 6px; font-size: 10px;">
            {seat_initial(@view, entry.player)}
          </span>
          {bid_action_label(entry.action, @lang)}
        </div>
      </div>

      <div style="display: grid; grid-template-columns: repeat(6, 1fr); gap: 6px; background: rgba(20,12,8,0.4); padding: 10px; border-radius: 8px; border: 1px solid rgba(212,181,114,0.2);">
        <button
          :for={b <- @bid_ladder}
          phx-click="bid_value"
          phx-value-bid={Integer.to_string(b.value)}
          disabled={!MapSet.member?(@legal_bid_values, b.value)}
          style={
            bid_ladder_button_style(b, MapSet.member?(@legal_bid_values, b.value), @view.highest_bid)
          }
        >
          <div style="font-size: 10px; opacity: 0.6; font-family: var(--font-mono);">{b.value}</div>
          <div>{if @lang == :sr, do: b.sr, else: b.en}</div>
          <div :if={b.suit} style={"color: #{suit_color_css(b.suit)}; font-size: 14px;"}>
            {Cards.suit_symbol(b.suit)}
          </div>
        </button>
      </div>

      <div style="display: flex; gap: 8px; flex-wrap: wrap; justify-content: center;">
        <button
          :if={@can_moje?}
          phx-click="bid_moje"
          style={action_button_style(:accent)}
        >
          {if @lang == :sr, do: "MOJE", else: "MINE"}
        </button>
        <button
          :if={@can_igra?}
          phx-click="bid_igra"
          phx-value-action="igra"
          style={action_button_style(:accent)}
        >
          {if @lang == :sr, do: "IGRA", else: "PLAY"}
        </button>
        <button
          :if={@can_igra_betl?}
          phx-click="bid_igra"
          phx-value-action="igra_betl"
          style={action_button_style(:accent)}
        >
          {if @lang == :sr, do: "IGRA BETL", else: "PLAY BETL"}
        </button>
        <button
          :if={@can_igra_sans?}
          phx-click="bid_igra"
          phx-value-action="igra_sans"
          style={action_button_style(:accent)}
        >
          {if @lang == :sr, do: "IGRA SANS", else: "PLAY SANS"}
        </button>
      </div>

      <button
        phx-click="bid"
        phx-value-action="dalje"
        disabled={!@can_pass?}
        style={pass_button_style(@can_pass?)}
      >
        {if @lang == :sr, do: "DALJE", else: "PASS"}
      </button>

      <div :if={!@view.is_my_turn} style={waiting_style()}>
        {waiting_text(@view, @lang)}
      </div>
    </div>
    """
  end

  defp bid_chip_style(:dalje) do
    "background: rgba(212,181,114,0.08); color: #d4b572; padding: 3px 10px; border-radius: 12px; font-family: var(--font-display); font-size: 12px; font-weight: 600; border: 1px solid #d4b57244;"
  end

  defp bid_chip_style(_) do
    "background: #d4b572; color: #2a1d10; padding: 3px 10px; border-radius: 12px; font-family: var(--font-display); font-size: 12px; font-weight: 600; border: 1px solid #d4b57244;"
  end

  defp bid_action_label(:dalje, :sr), do: "Dalje"
  defp bid_action_label(:dalje, _), do: "Pass"
  defp bid_action_label(:moje, :sr), do: "Moje"
  defp bid_action_label(:moje, _), do: "Mine"

  defp bid_action_label({:moje, v}, lang),
    do: "#{bid_action_label(:moje, lang)} (#{bid_label(v, lang)})"

  defp bid_action_label(:igra, :sr), do: "Igra"
  defp bid_action_label(:igra, _), do: "Play"
  defp bid_action_label(:igra_betl, :sr), do: "Igra Betl"
  defp bid_action_label(:igra_betl, _), do: "Play Betl"
  defp bid_action_label(:igra_sans, :sr), do: "Igra Sans"
  defp bid_action_label(:igra_sans, _), do: "Play Sans"
  defp bid_action_label({:bid, v}, lang), do: bid_label(v, lang)
  defp bid_action_label(other, _), do: inspect(other)

  defp bid_label(2, _), do: "Pik"
  defp bid_label(3, _), do: "Karo"
  defp bid_label(4, _), do: "Herc"
  defp bid_label(5, _), do: "Tref"
  defp bid_label(6, _), do: "Betl"
  defp bid_label(7, _), do: "Sans"
  defp bid_label(n, _), do: Integer.to_string(n)

  defp bid_ladder_button_style(b, legal?, highest_bid) do
    is_high = highest_bid == b.value

    base = """
    border-radius: 6px; padding: 8px 4px;
    font-family: var(--font-display); font-size: 13px; font-weight: 600;
    display: flex; flex-direction: column; align-items: center; gap: 2px;
    min-width: 60px; transition: all 120ms;
    """

    state =
      cond do
        is_high ->
          "background: #d4b572; color: #2a1d10; border: 1px solid #d4b572; cursor: not-allowed;"

        legal? ->
          "background: rgba(245,233,212,0.08); color: #f5e9d4; border: 1px solid rgba(212,181,114,0.3); cursor: pointer;"

        true ->
          "background: rgba(60,40,20,0.3); color: #d4b57244; border: 1px solid rgba(212,181,114,0.3); cursor: not-allowed;"
      end

    base <> state
  end

  defp suit_color_css(suit) do
    if Cards.suit_color(suit) == :red, do: "#d96666", else: "#f5e9d4"
  end

  ## ----------------------------------------------------------------- Discard

  attr :view, :map, required: true
  attr :selected, :any, required: true, doc: "MapSet of selected card tuples"
  attr :talon_taken, :boolean, default: false
  attr :lang, :atom, default: :sr

  def discard_panel(assigns) do
    is_declarer = assigns.view.my_seat == assigns.view.declarer
    selected_count = MapSet.size(assigns.selected)

    assigns =
      assigns
      |> assign(:is_declarer?, is_declarer)
      |> assign(:selected_count, selected_count)

    ~H"""
    <div style="display: flex; flex-direction: column; align-items: center; gap: 12px;">
      <.phase_banner phase={:discard} lang={@lang} />

      <div
        :if={@is_declarer? and not @talon_taken}
        style="display: flex; flex-direction: column; align-items: center; gap: 12px;"
      >
        <div style="color: #f5e9d4; font-family: var(--font-display); font-size: 16px; text-align: center;">
          {if @lang == :sr, do: "Talon je otkriven", else: "Talon is revealed"}
        </div>
        <div style="color: #d4b57299; font-family: var(--font-mono); font-size: 11px; text-align: center; max-width: 360px;">
          {if @lang == :sr,
            do: "Uzmi obe karte u ruku",
            else: "Take both cards into your hand"}
        </div>
        <button
          phx-click="take_talon"
          style={action_button_style(:primary)}
          id="take-talon-btn"
        >
          {if @lang == :sr, do: "UZMI", else: "TAKE"}
        </button>
      </div>

      <div
        :if={@is_declarer? and @talon_taken}
        style="display: flex; flex-direction: column; align-items: center; gap: 12px;"
      >
        <div style="color: #f5e9d4; font-family: var(--font-display); font-size: 16px; text-align: center;">
          {if @lang == :sr, do: "Baci 2 karte (skrivene)", else: "Discard 2 cards (hidden)"}
        </div>
        <div style="color: #d4b57299; font-family: var(--font-mono); font-size: 11px; text-align: center; max-width: 360px;">
          {if @lang == :sr,
            do: "Klikni dve karte u svojoj ruci",
            else: "Click two cards in your hand"}
        </div>
        <div style="font-family: var(--font-mono); color: #d4b572; font-size: 13px;">
          {@selected_count} / 2
        </div>
        <button
          :if={@selected_count == 2}
          phx-click="confirm_discard"
          style={action_button_style(:primary)}
          id="confirm-discard-btn"
        >
          {if @lang == :sr, do: "BACI", else: "DISCARD"}
        </button>
        <button
          :if={@selected_count != 2}
          disabled
          style={action_button_style(:disabled)}
        >
          {if @lang == :sr, do: "BACI", else: "DISCARD"}
        </button>
      </div>

      <div :if={!@is_declarer?} style={waiting_style()}>
        {waiting_text(@view, @lang)}
      </div>
    </div>
    """
  end

  ## ----------------------------------------------------------------- Declare

  attr :view, :map, required: true
  attr :lang, :atom, default: :sr

  def declare_panel(assigns) do
    declare_options =
      assigns.view.legal_actions
      |> Enum.filter(&match?({:declare, _}, &1))
      |> Enum.map(fn {:declare, game} -> game end)

    assigns = assign(assigns, :declare_options, declare_options)

    ~H"""
    <div style="display: flex; flex-direction: column; align-items: center; gap: 14px;">
      <.phase_banner phase={:declare_game} lang={@lang} />

      <div
        :if={@view.is_my_turn}
        style="display: flex; flex-direction: column; align-items: center; gap: 14px;"
      >
        <div style="color: #f5e9d4; font-family: var(--font-display); font-size: 16px;">
          {if @lang == :sr, do: "Izaberi konačnu igru", else: "Choose final contract"}
        </div>
        <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px;">
          <button
            :for={game <- @declare_options}
            phx-click="declare_game"
            phx-value-game={Atom.to_string(game)}
            style={declare_button_style()}
          >
            <div>{game_name(game, @lang)}</div>
            <div
              :if={game in [:pik, :karo, :herc, :tref]}
              style={"font-size: 18px; color: #{suit_color_css(game)};"}
            >
              {Cards.suit_symbol(game)}
            </div>
          </button>
        </div>
      </div>

      <div :if={!@view.is_my_turn} style={waiting_style()}>
        {waiting_text(@view, @lang)}
      </div>
    </div>
    """
  end

  defp declare_button_style do
    """
    padding: 12px 18px; min-width: 110px;
    background: transparent; color: #d4b572;
    border: 1px solid #d4b572aa; border-radius: 4px;
    font-family: var(--font-display); font-size: 13px;
    letter-spacing: 0.15em; font-weight: 600;
    text-transform: uppercase; cursor: pointer;
    display: flex; flex-direction: column; align-items: center; gap: 4px;
    """
  end

  defp game_name(:pik, :sr), do: "Pik"
  defp game_name(:pik, _), do: "Spades"
  defp game_name(:karo, :sr), do: "Karo"
  defp game_name(:karo, _), do: "Diamonds"
  defp game_name(:herc, :sr), do: "Herc"
  defp game_name(:herc, _), do: "Hearts"
  defp game_name(:tref, :sr), do: "Tref"
  defp game_name(:tref, _), do: "Clubs"
  defp game_name(:betl, _), do: "Betl"
  defp game_name(:sans, _), do: "Sans"
  defp game_name(other, _), do: to_string(other)

  ## ----------------------------------------------------------------- Defense

  attr :view, :map, required: true
  attr :lang, :atom, default: :sr

  def defense_panel(assigns) do
    ~H"""
    <div style="display: flex; flex-direction: column; align-items: center; gap: 14px; min-width: 380px;">
      <.phase_banner phase={:defense} lang={@lang} />

      <div
        :if={@view.game_type}
        style="color: #f5e9d4; font-family: var(--font-display); font-size: 14px; text-align: center;"
      >
        {seat_name(@view, @view.declarer)} — {game_name(@view.game_type, @lang)}
        <span
          :if={@view.game_type in [:pik, :karo, :herc, :tref]}
          style={"color: #{suit_color_css(@view.game_type)};"}
        >
          {Cards.suit_symbol(@view.game_type)}
        </span>
      </div>

      <div style="color: #f5e9d4; font-family: var(--font-display); font-size: 16px;">
        {if @lang == :sr, do: "Igraš ili ne?", else: "Are you in?"}
      </div>

      <div style="display: flex; gap: 12px; margin-top: 4px;">
        <div
          :for={seat <- defender_seats(@view)}
          style={defense_chip_style(@view.defense_responses[seat])}
        >
          <span style="font-size: 10px; opacity: 0.7; margin-right: 6px;">
            {seat_initial(@view, seat)}
          </span>
          {defense_chip_label(@view.defense_responses[seat], @lang)}
        </div>
      </div>

      <div
        :if={@view.is_my_turn}
        style="display: flex; gap: 8px; margin-top: 6px; flex-wrap: wrap; justify-content: center;"
      >
        <button
          :if={:dodjem in @view.legal_actions}
          phx-click="defense"
          phx-value-action="dodjem"
          style={action_button_style(:primary)}
        >
          {if @lang == :sr, do: "DOĐEM", else: "IN"}
        </button>
        <button
          :if={:ne_dodjem in @view.legal_actions}
          phx-click="defense"
          phx-value-action="ne_dodjem"
          style={action_button_style(:secondary)}
        >
          {if @lang == :sr, do: "NE DOĐEM", else: "OUT"}
        </button>
        <button
          :if={:poziv in @view.legal_actions}
          phx-click="defense"
          phx-value-action="poziv"
          style={action_button_style(:secondary)}
        >
          {if @lang == :sr, do: "POZIV", else: "INVITE"}
        </button>
        <button
          :if={:sam in @view.legal_actions}
          phx-click="defense"
          phx-value-action="sam"
          style={action_button_style(:primary)}
        >
          {if @lang == :sr, do: "SAM", else: "ALONE"}
        </button>
        <button
          :if={:idemo_zajedno in @view.legal_actions}
          phx-click="defense"
          phx-value-action="idemo_zajedno"
          style={action_button_style(:accent)}
        >
          {if @lang == :sr, do: "IDEMO ZAJEDNO", else: "PLAY TOGETHER"}
        </button>
      </div>

      <div :if={!@view.is_my_turn} style={waiting_style()}>
        {waiting_text(@view, @lang)}
      </div>
    </div>
    """
  end

  defp defender_seats(view) do
    [0, 1, 2] |> Enum.reject(&(&1 == view.declarer))
  end

  defp defense_chip_style(nil) do
    "background: rgba(212,181,114,0.1); color: #d4b57299; padding: 8px 14px; border-radius: 6px; font-family: var(--font-display); font-size: 13px; border: 1px solid #d4b57244;"
  end

  defp defense_chip_style(_) do
    "background: #d4b572; color: #2a1d10; padding: 8px 14px; border-radius: 6px; font-family: var(--font-display); font-size: 13px; border: 1px solid #d4b57244;"
  end

  defp defense_chip_label(nil, _), do: "…"
  defp defense_chip_label(:dodjem, :sr), do: "Dođem"
  defp defense_chip_label(:dodjem, _), do: "In"
  defp defense_chip_label(:ne_dodjem, :sr), do: "Ne dođem"
  defp defense_chip_label(:ne_dodjem, _), do: "Out"
  defp defense_chip_label(:poziv, :sr), do: "Poziv"
  defp defense_chip_label(:poziv, _), do: "Invite"
  defp defense_chip_label(:sam, :sr), do: "Sam"
  defp defense_chip_label(:sam, _), do: "Alone"
  defp defense_chip_label(:idemo_zajedno, :sr), do: "Idemo"
  defp defense_chip_label(:idemo_zajedno, _), do: "Together"
  defp defense_chip_label(other, _), do: to_string(other)

  ## ----------------------------------------------------------------- Kontra

  attr :view, :map, required: true
  attr :lang, :atom, default: :sr

  def kontra_panel(assigns) do
    next_label = next_kontra_label(assigns.view.kontra_level, assigns.lang)
    current_label = current_kontra_label(assigns.view.kontra_level, assigns.lang)

    next_action =
      cond do
        :kontra in assigns.view.legal_actions -> "kontra"
        :rekontra in assigns.view.legal_actions -> "rekontra"
        :subkontra in assigns.view.legal_actions -> "subkontra"
        :mortkontra in assigns.view.legal_actions -> "mortkontra"
        true -> nil
      end

    can_pass? = :moze in assigns.view.legal_actions

    assigns =
      assigns
      |> assign(:next_label, next_label)
      |> assign(:current_label, current_label)
      |> assign(:next_action, next_action)
      |> assign(:can_pass?, can_pass?)

    ~H"""
    <div style="display: flex; flex-direction: column; align-items: center; gap: 14px;">
      <.phase_banner phase={:kontra} lang={@lang} />

      <div style="color: #f5e9d4; font-family: var(--font-display); font-size: 16px; text-align: center;">
        <%= if @view.kontra_level == 0 do %>
          {if @lang == :sr, do: "Hoćeš kontra?", else: "Call kontra?"}
        <% else %>
          {if @lang == :sr, do: "Trenutno: #{@current_label}", else: "Current: #{@current_label}"}
        <% end %>
      </div>

      <div :if={@view.is_my_turn} style="display: flex; gap: 8px;">
        <button
          :if={@next_action}
          phx-click="kontra"
          phx-value-action={@next_action}
          style={kontra_button_style()}
        >
          {String.upcase(@next_label)}
        </button>
        <button
          :if={@can_pass?}
          phx-click="kontra"
          phx-value-action="moze"
          style={action_button_style(:secondary)}
        >
          {if @lang == :sr, do: "DALJE", else: "PASS"}
        </button>
      </div>

      <div :if={!@view.is_my_turn} style={waiting_style()}>
        {waiting_text(@view, @lang)}
      </div>
    </div>
    """
  end

  defp kontra_button_style do
    """
    padding: 10px 24px;
    background: #8a1f1f; color: #f5e9d4;
    border: 1px solid #2a1d10; border-radius: 4px;
    font-family: var(--font-display); font-size: 13px;
    letter-spacing: 0.15em; font-weight: 600;
    cursor: pointer; text-transform: uppercase;
    box-shadow: 0 2px 8px rgba(0,0,0,0.3);
    """
  end

  defp current_kontra_label(1, :sr), do: "Kontra"
  defp current_kontra_label(1, _), do: "Kontra"
  defp current_kontra_label(2, _), do: "Rekontra"
  defp current_kontra_label(3, _), do: "Subkontra"
  defp current_kontra_label(4, _), do: "Mortkontra"
  defp current_kontra_label(_, _), do: ""

  defp next_kontra_label(0, _), do: "Kontra"
  defp next_kontra_label(1, _), do: "Rekontra"
  defp next_kontra_label(2, _), do: "Subkontra"
  defp next_kontra_label(3, _), do: "Mortkontra"
  defp next_kontra_label(_, _), do: ""

  ## ----------------------------------------------------------------- Trick area

  attr :view, :map, required: true
  attr :positions, :map, required: true, doc: "%{left:, right:, bottom:}"
  attr :lang, :atom, default: :sr

  def trick_area(assigns) do
    ~H"""
    <div style="display: grid; grid-template-areas: 'l . r' '. s .'; grid-template-rows: 200px 200px; grid-template-columns: 140px 140px 140px; gap: 0; justify-content: center; align-items: center; width: 420px; height: 400px; position: relative;">
      <div
        :for={p <- @view.current_trick}
        style={trick_card_slot_style(p.player, @positions)}
      >
        <.card card={p.card} size={:xl} />
      </div>
    </div>
    """
  end

  defp trick_card_slot_style(seat, positions) do
    {area, rotate} =
      cond do
        seat == positions.bottom -> {"s", 0}
        seat == positions.left -> {"l", -8}
        seat == positions.right -> {"r", 8}
        true -> {"s", 0}
      end

    """
    grid-area: #{area};
    display: flex; justify-content: center; align-items: center;
    transform: rotate(#{rotate}deg);
    animation: pf-card-in 240ms ease-out;
    """
  end

  ## ----------------------------------------------------------------- Scoring

  attr :view, :map, required: true
  attr :lang, :atom, default: :sr

  def scoring_panel(assigns) do
    ~H"""
    <div style="display: flex; flex-direction: column; align-items: center; gap: 12px; min-width: 360px;">
      <.phase_banner phase={:hand_over} lang={@lang} />

      <div :if={@view.scoring_result} style={scoring_card_style()}>
        <%= cond do %>
          <% @view.scoring_result.all_passed -> %>
            <div style="font-family: var(--font-display); font-size: 20px; margin-bottom: 8px; text-align: center;">
              {if @lang == :sr, do: "SVI DALJE — REFE", else: "ALL PASSED — REFE"}
            </div>
          <% @view.scoring_result.free_pass -> %>
            <div style="font-family: var(--font-display); font-size: 20px; margin-bottom: 8px; text-align: center;">
              {if @lang == :sr, do: "FREE PASS", else: "FREE PASS"}
            </div>
            <div style="text-align: center; font-size: 14px; margin-bottom: 10px;">
              {game_name(@view.scoring_result.game_type, @lang)}
            </div>
          <% true -> %>
            <div style="font-family: var(--font-display); font-size: 20px; margin-bottom: 8px; text-align: center;">
              {made_failed_label(@view.scoring_result.declarer_passed, @lang)}
            </div>
            <div style="text-align: center; font-size: 14px; margin-bottom: 10px;">
              {seat_name(@view, @view.declarer)} · {game_name(@view.scoring_result.game_type, @lang)}
            </div>
        <% end %>

        <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; margin-top: 10px; padding-top: 10px; border-top: 1px dashed rgba(60,40,20,0.4);">
          <div :for={seat <- [0, 1, 2]} style="text-align: center;">
            <div style="font-size: 11px; font-family: var(--font-mono); opacity: 0.7;">
              {seat_name(@view, seat)}
            </div>
            <div style="font-size: 10px; font-family: var(--font-mono); opacity: 0.55; margin: 2px 0;">
              {Enum.at(@view.scoring_result.tricks, seat)} {if @lang == :sr, do: "štih.", else: "tr."}
            </div>
            <div style={"font-family: var(--font-display); font-size: 22px; font-weight: 700; color: #{bule_color(Enum.at(@view.scoring_result.bule_changes, seat))};"}>
              {format_bule_change(Enum.at(@view.scoring_result.bule_changes, seat))}
            </div>
          </div>
        </div>
      </div>

      <button
        phx-click="next_hand"
        style={action_button_style(:primary)}
        id="next-hand-btn"
      >
        {if @lang == :sr, do: "SLEDEĆA RUKA →", else: "NEXT HAND →"}
      </button>
    </div>
    """
  end

  defp scoring_card_style do
    """
    background: rgba(245,233,212,0.96); color: #2a1d10;
    padding: 18px 28px; border-radius: 4px;
    box-shadow: 0 8px 24px rgba(0,0,0,0.5);
    font-family: var(--font-hand); min-width: 320px;
    """
  end

  defp made_failed_label(true, :sr), do: "PROŠAO"
  defp made_failed_label(true, _), do: "MADE"
  defp made_failed_label(false, :sr), do: "PAO"
  defp made_failed_label(false, _), do: "FAILED"

  defp bule_color(0), do: "rgba(60,40,20,0.4)"
  defp bule_color(n) when n < 0, do: "#2a1d10"
  defp bule_color(_), do: "#8a1f1f"

  defp format_bule_change(0), do: "±0"
  defp format_bule_change(n) when n < 0, do: "+#{-n}"
  defp format_bule_change(n), do: "−#{n}"

  ## ----------------------------------------------------------------- Shared helpers

  defp seat_name(view, seat), do: Map.get(view.display_names, seat, "Seat #{seat}")
  defp seat_initial(view, seat), do: view |> seat_name(seat) |> String.first()

  defp waiting_style do
    "color: #d4b57299; font-family: var(--font-mono); font-size: 11px; letter-spacing: 0.15em;"
  end

  defp waiting_text(view, :sr) do
    "čeka #{seat_name(view, view.current_player)}…"
  end

  defp waiting_text(view, _) do
    "waiting for #{seat_name(view, view.current_player)}…"
  end

  defp action_button_style(:primary) do
    """
    padding: 10px 24px;
    background: #d4b572; color: #2a1d10;
    border: 1px solid #2a1d10; border-radius: 4px;
    font-family: var(--font-display); font-size: 13px;
    letter-spacing: 0.15em; font-weight: 600;
    cursor: pointer; text-transform: uppercase;
    box-shadow: 0 2px 8px rgba(0,0,0,0.3);
    """
  end

  defp action_button_style(:secondary) do
    """
    padding: 10px 24px;
    background: transparent; color: #d4b572;
    border: 1px solid #d4b572aa; border-radius: 4px;
    font-family: var(--font-display); font-size: 13px;
    letter-spacing: 0.15em; font-weight: 600;
    cursor: pointer; text-transform: uppercase;
    """
  end

  defp action_button_style(:accent) do
    """
    padding: 10px 24px;
    background: #8a1f1f; color: #f5e9d4;
    border: 1px solid #2a1d10; border-radius: 4px;
    font-family: var(--font-display); font-size: 13px;
    letter-spacing: 0.15em; font-weight: 600;
    cursor: pointer; text-transform: uppercase;
    """
  end

  defp action_button_style(:disabled) do
    """
    padding: 10px 24px;
    background: rgba(60,40,20,0.4); color: #d4b57244;
    border: 1px solid #d4b57222; border-radius: 4px;
    font-family: var(--font-display); font-size: 13px;
    letter-spacing: 0.15em; font-weight: 600;
    cursor: not-allowed; text-transform: uppercase;
    """
  end

  defp pass_button_style(true) do
    "padding: 6px 24px; background: transparent; color: #d4b572; border: 1px solid #d4b57266; border-radius: 4px; font-family: var(--font-display); font-size: 13px; letter-spacing: 0.1em; cursor: pointer;"
  end

  defp pass_button_style(false) do
    "padding: 6px 24px; background: rgba(60,40,20,0.3); color: #d4b57244; border: 1px solid #d4b57266; border-radius: 4px; font-family: var(--font-display); font-size: 13px; letter-spacing: 0.1em; cursor: not-allowed;"
  end
end
