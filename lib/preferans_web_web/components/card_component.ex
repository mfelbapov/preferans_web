defmodule PreferansWebWeb.CardComponent do
  @moduledoc """
  Single playing card. Cream face with TL/BR corner indices and a large center
  pip; burgundy diagonal-stripe back with an inset border and "P" monogram.
  """
  use Phoenix.Component

  alias PreferansWeb.Game.Cards

  @sizes %{
    xs: %{w: 28, h: 40, font: 11, sym: 9, corner: 4, pip_ratio: 0.42},
    sm: %{w: 44, h: 64, font: 14, sym: 12, corner: 6, pip_ratio: 0.42},
    md: %{w: 64, h: 92, font: 20, sym: 18, corner: 6, pip_ratio: 0.42},
    lg: %{w: 80, h: 116, font: 26, sym: 22, corner: 8, pip_ratio: 0.42},
    # Legacy aliases used by step-5 callers; remove once those are rewritten.
    small: %{w: 44, h: 64, font: 14, sym: 12, corner: 6, pip_ratio: 0.42},
    normal: %{w: 64, h: 92, font: 20, sym: 18, corner: 6, pip_ratio: 0.42}
  }

  attr :card, :any, default: nil, doc: "{suit, rank} tuple or nil for face-down"
  attr :face, :atom, default: :up, doc: ":up or :down"
  attr :clickable, :boolean, default: false
  attr :selected, :boolean, default: false
  attr :dimmed, :boolean, default: false
  attr :size, :atom, default: :md, doc: ":xs | :sm | :md | :lg"
  attr :click_event, :string, default: nil
  attr :click_value, :string, default: nil
  attr :id, :string, default: nil

  def card(assigns) do
    dims = Map.fetch!(@sizes, assigns.size)

    assigns =
      assigns
      |> assign(:dims, dims)
      |> assign(:back?, assigns.face == :down or is_nil(assigns.card))

    ~H"""
    <div :if={@back?} style={back_style(@dims)} class="pf-card pf-card-back">
      <div style={back_inset_style(@dims)}></div>
      <div style={back_monogram_style(@dims)}>P</div>
    </div>
    <div
      :if={!@back?}
      id={@id}
      phx-click={@click_event}
      phx-value-card={@click_value}
      style={face_style(@dims, @selected, @dimmed, @clickable)}
      class={["pf-card pf-card-face", @clickable && "cursor-pointer"]}
    >
      <% {suit, rank} = @card %>
      <% color = if Cards.suit_color(suit) == :red, do: "var(--card-red)", else: "var(--card-black)" %>
      <div style={corner_style(:tl, @dims, color)}>
        <span>{Cards.rank_label(rank)}</span>
        <span style={"font-size: #{@dims.sym}px; margin-top: -2px;"}>{Cards.suit_symbol(suit)}</span>
      </div>
      <div style={corner_style(:br, @dims, color)}>
        <span>{Cards.rank_label(rank)}</span>
        <span style={"font-size: #{@dims.sym}px; margin-top: -2px;"}>{Cards.suit_symbol(suit)}</span>
      </div>
      <div style={pip_style(@dims, color)}>{Cards.suit_symbol(suit)}</div>
    </div>
    """
  end

  defp face_style(dims, selected, dimmed, clickable) do
    base = """
    width: #{dims.w}px; height: #{dims.h}px;
    border: 1px solid #1a1410; border-radius: #{dims.corner}px;
    background: var(--card-bg); position: relative; overflow: hidden;
    user-select: none; flex-shrink: 0;
    transition: transform 160ms cubic-bezier(.2,.7,.2,1), box-shadow 160ms;
    """

    state =
      cond do
        selected ->
          "opacity: 1; transform: translateY(-12px); box-shadow: 0 -8px 0 -2px var(--accent), 0 12px 24px rgba(0,0,0,0.35);"

        dimmed ->
          "opacity: 0.42; box-shadow: 0 4px 10px rgba(0,0,0,0.28);"

        clickable ->
          "opacity: 1; box-shadow: 0 4px 10px rgba(0,0,0,0.28);"

        true ->
          "opacity: 1; box-shadow: 0 4px 10px rgba(0,0,0,0.28);"
      end

    base <> state
  end

  defp corner_style(:tl, dims, color) do
    """
    position: absolute; top: 4px; left: 6px; color: #{color};
    font-family: var(--font-card); font-size: #{dims.font}px;
    line-height: 1; font-weight: 600; letter-spacing: -0.02em;
    display: flex; flex-direction: column; align-items: center;
    """
  end

  defp corner_style(:br, dims, color) do
    """
    position: absolute; bottom: 4px; right: 6px; color: #{color};
    font-family: var(--font-card); font-size: #{dims.font}px;
    line-height: 1; font-weight: 600; letter-spacing: -0.02em;
    transform: rotate(180deg);
    display: flex; flex-direction: column; align-items: center;
    """
  end

  defp pip_style(dims, color) do
    pip_size = round(dims.h * dims.pip_ratio)

    """
    position: absolute; inset: 0;
    display: flex; align-items: center; justify-content: center;
    color: #{color}; font-size: #{pip_size}px; line-height: 1; opacity: 0.9;
    """
  end

  defp back_style(dims) do
    """
    width: #{dims.w}px; height: #{dims.h}px;
    border-radius: #{dims.corner}px; border: 1px solid #1a1410;
    background: repeating-linear-gradient(45deg, #6b1d1d 0 6px, #561414 6px 12px);
    box-shadow: 0 4px 10px rgba(0,0,0,0.3);
    position: relative; flex-shrink: 0;
    """
  end

  defp back_inset_style(dims) do
    """
    position: absolute; inset: 4px;
    border: 1px solid rgba(255,220,180,0.25);
    border-radius: #{max(dims.corner - 2, 0)}px;
    """
  end

  defp back_monogram_style(dims) do
    size = round(dims.h * 0.28)

    """
    position: absolute; inset: 0;
    display: flex; align-items: center; justify-content: center;
    color: rgba(255,220,180,0.5); font-family: var(--font-display);
    font-size: #{size}px; font-weight: 700; letter-spacing: 0.05em;
    """
  end
end
