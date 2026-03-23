defmodule PreferansWebWeb.CardComponent do
  @moduledoc """
  Function component for rendering a single playing card.
  CSS-only rendering — structured so SVG swap is easy later.
  """
  use Phoenix.Component

  alias PreferansWeb.Game.Cards

  attr :card, :any, default: nil, doc: "{suit, rank} tuple or nil for face-down"
  attr :face, :atom, default: :up, doc: ":up or :down"
  attr :clickable, :boolean, default: false
  attr :selected, :boolean, default: false
  attr :dimmed, :boolean, default: false
  attr :size, :atom, default: :normal, doc: ":normal or :small"
  attr :click_event, :string, default: nil
  attr :click_value, :string, default: nil
  attr :id, :string, default: nil

  def card(assigns) do
    assigns =
      assign_new(assigns, :dom_id, fn ->
        assigns[:id]
      end)

    ~H"""
    <%= if @face == :down or @card == nil do %>
      <div class={card_back_classes(@size)} />
    <% else %>
      <% {suit, rank} = @card %>
      <% color_class = if Cards.suit_color(suit) == :red, do: "text-card-red", else: "text-card-black" %>
      <div
        id={@dom_id}
        class={card_face_classes(@size, @clickable, @selected, @dimmed)}
        phx-click={@click_event}
        phx-value-card={@click_value}
      >
        <div class={["absolute top-0.5 left-1 leading-none text-center", color_class]}>
          <div class={rank_class(@size)}>{Cards.rank_label(rank)}</div>
          <div class={suit_small_class(@size)}>{Cards.suit_symbol(suit)}</div>
        </div>
        <div class={["absolute inset-0 flex items-center justify-center", color_class]}>
          <span class={suit_center_class(@size)}>{Cards.suit_symbol(suit)}</span>
        </div>
        <div class={[
          "absolute bottom-0.5 right-1 leading-none text-center rotate-180",
          color_class
        ]}>
          <div class={rank_class(@size)}>{Cards.rank_label(rank)}</div>
          <div class={suit_small_class(@size)}>{Cards.suit_symbol(suit)}</div>
        </div>
      </div>
    <% end %>
    """
  end

  defp card_face_classes(size, clickable, selected, dimmed) do
    base = [
      "relative rounded-lg border bg-card-cream select-none transition-transform duration-150",
      if(size == :small, do: "w-[60px] h-[84px]", else: "w-[90px] h-[126px]")
    ]

    state =
      cond do
        selected ->
          "border-blue-400 -translate-y-3 ring-2 ring-blue-400 z-10 shadow-lg"

        dimmed ->
          "border-stone-300 opacity-40 cursor-default shadow-sm"

        clickable ->
          "border-stone-300 cursor-pointer hover:scale-105 hover:-translate-y-1 shadow-sm"

        true ->
          "border-stone-300 shadow-sm"
      end

    (base ++ [state])
    |> List.flatten()
    |> Enum.join(" ")
  end

  defp card_back_classes(size) do
    size_class = if size == :small, do: "w-[60px] h-[84px]", else: "w-[90px] h-[126px]"

    "#{size_class} rounded-lg border-2 border-card-back-border bg-card-back select-none card-back-pattern"
  end

  defp rank_class(:small), do: "text-xs font-bold"
  defp rank_class(_), do: "text-sm font-bold"

  defp suit_small_class(:small), do: "text-[10px] -mt-0.5"
  defp suit_small_class(_), do: "text-xs -mt-0.5"

  defp suit_center_class(:small), do: "text-2xl"
  defp suit_center_class(_), do: "text-4xl"
end
