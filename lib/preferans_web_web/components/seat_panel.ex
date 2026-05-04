defmodule PreferansWebWeb.SeatPanel do
  @moduledoc """
  Per-opponent seat: avatar + name + role badge, action bubble, trick count,
  fanned face-down hand. Visual port of `seat-panel.jsx`.
  """
  use Phoenix.Component

  import PreferansWebWeb.CardComponent

  @doc """
  ## Attrs
    * `name` — display name shown next to the avatar.
    * `avatar_color` — CSS color for the avatar disk background.
    * `card_count` — number of (face-down) cards to fan.
    * `tricks` — tricks won this hand.
    * `dealer?` / `declarer?` / `partner?` / `out?` — role flags.
    * `current_action` — optional short text for the action bubble (e.g. "Pas").
    * `side` — `:left | :right`. Flips alignment + row direction.
    * `reveal_hand?` — render face-up cards instead of backs (debug).
    * `cards` — only used when `reveal_hand?` is true; list of `{suit, rank}`.
    * `lang` — `:sr | :en`.
  """
  attr :name, :string, required: true
  attr :avatar_color, :string, default: "#3a4a5a"
  attr :card_count, :integer, default: 10
  attr :tricks, :integer, default: 0
  attr :dealer?, :boolean, default: false
  attr :declarer?, :boolean, default: false
  attr :partner?, :boolean, default: false
  attr :out?, :boolean, default: false
  attr :current_action, :string, default: nil
  attr :side, :atom, default: :left
  attr :reveal_hand?, :boolean, default: false
  attr :cards, :list, default: []
  attr :lang, :atom, default: :sr

  def seat_panel(assigns) do
    ~H"""
    <div class="pf-seat" style={outer_style(@side, @out?)}>
      <div style={header_row_style(@side)}>
        <div style={avatar_style(@avatar_color)}>
          {String.first(@name)}
          <div :if={@dealer?} style={dealer_badge_style()}>D</div>
        </div>
        <div style={"text-align: #{align(@side)};"}>
          <div style="font-family: var(--font-display); font-size: 18px; color: #f5e9d4; letter-spacing: 0.02em;">
            {@name}
          </div>
          <div style="font-family: var(--font-mono); font-size: 11px; color: #d4b572; text-transform: uppercase; letter-spacing: 0.1em;">
            {role_label(assigns)}
          </div>
        </div>
      </div>

      <div :if={@current_action} style={bubble_style(@side)}>
        {@current_action}
      </div>

      <div :if={@out?} style={out_chip_style()}>
        {if @lang == :sr, do: "Ne dođem", else: "Out"}
      </div>

      <div style={trick_row_style(@side)}>
        <div style="font-size: 10px; color: #d4b57299; text-transform: uppercase; letter-spacing: 0.15em;">
          {if @lang == :sr, do: "Štih", else: "Tricks"}
        </div>
        <div style={"font-family: var(--font-display); font-size: 18px; font-weight: 700; color: #{if @tricks > 0, do: "#d4b572", else: "#d4b57266"};"}>
          {@tricks}<span style="font-size: 12px; opacity: 0.5;">/10</span>
        </div>
      </div>

      <div style={hand_row_style(@side)}>
        <div style={fan_inner_style(@card_count)}>
          <div :for={i <- 0..max(@card_count - 1, 0)} style={fan_card_style(i, @card_count)}>
            <%= if @reveal_hand? and Enum.at(@cards, i) do %>
              <.card card={Enum.at(@cards, i)} size={:sm} />
            <% else %>
              <.card face={:down} size={:sm} />
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp role_label(%{declarer?: true, lang: :sr}), do: "IGRA"
  defp role_label(%{declarer?: true}), do: "DECLARER"
  defp role_label(%{partner?: true, lang: :sr}), do: "POZIV"
  defp role_label(%{partner?: true}), do: "PARTNER"
  defp role_label(%{dealer?: true, lang: :sr}), do: "Dele"
  defp role_label(%{dealer?: true}), do: "Dealer"
  defp role_label(%{lang: :sr}), do: "IGRAČ"
  defp role_label(_), do: "PLAYER"

  defp align(:left), do: "left"
  defp align(:right), do: "right"

  defp outer_style(side, out?) do
    align_items = if side == :left, do: "flex-start", else: "flex-end"

    """
    width: 100%; display: flex; flex-direction: column;
    align-items: #{align_items}; gap: 14px; padding: 14px;
    opacity: #{if out?, do: "0.55", else: "1"};
    transition: opacity 200ms;
    """
  end

  defp header_row_style(side) do
    direction = if side == :left, do: "row", else: "row-reverse"

    """
    display: flex; align-items: center; gap: 12px;
    flex-direction: #{direction};
    """
  end

  defp avatar_style(color) do
    """
    width: 56px; height: 56px; border-radius: 50%;
    background: #{color};
    display: flex; align-items: center; justify-content: center;
    color: #f5e9d4; font-family: var(--font-display); font-size: 22px; font-weight: 700;
    border: 2px solid rgba(0,0,0,0.3);
    box-shadow: inset 0 -8px 16px rgba(0,0,0,0.25), 0 2px 8px rgba(0,0,0,0.4);
    position: relative;
    """
  end

  defp dealer_badge_style do
    """
    position: absolute; bottom: -4px; right: -4px;
    background: #d4b572; color: #2a1d10;
    border-radius: 50%; width: 22px; height: 22px;
    display: flex; align-items: center; justify-content: center;
    font-family: var(--font-mono); font-size: 11px; font-weight: 700;
    border: 1px solid #2a1d10;
    """
  end

  defp bubble_style(side) do
    align_self = if side == :left, do: "flex-start", else: "flex-end"

    margin =
      if side == :left, do: "margin-left: 8px;", else: "margin-right: 8px;"

    """
    background: #f5e9d4; color: #2a1d10;
    padding: 6px 12px; border-radius: 16px;
    font-family: var(--font-display); font-size: 14px; font-weight: 600;
    box-shadow: 0 2px 8px rgba(0,0,0,0.3);
    align-self: #{align_self};
    #{margin}
    position: relative; max-width: 200px;
    """
  end

  defp out_chip_style do
    """
    font-family: var(--font-mono); font-size: 11px; color: #d4b572;
    letter-spacing: 0.1em; text-transform: uppercase;
    padding: 2px 8px; border: 1px solid #d4b57255; border-radius: 4px;
    """
  end

  defp trick_row_style(side) do
    direction = if side == :left, do: "row", else: "row-reverse"

    """
    display: flex; gap: 6px; align-items: baseline;
    flex-direction: #{direction};
    font-family: var(--font-mono);
    """
  end

  defp hand_row_style(side) do
    justify = if side == :left, do: "flex-start", else: "flex-end"

    """
    position: relative; min-height: 92px; width: 100%;
    display: flex; justify-content: #{justify};
    """
  end

  defp fan_inner_style(card_count) do
    width = max(60, 18 * (card_count - 1) + 64)
    "position: relative; height: 92px; width: #{width}px;"
  end

  defp fan_card_style(i, card_count) do
    rotation = (i - card_count / 2) * 0.6

    """
    position: absolute; left: #{i * 18}px; top: 0;
    transform: rotate(#{rotation}deg);
    transform-origin: bottom center;
    """
  end
end
