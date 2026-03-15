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

  def card(assigns) do
    ~H"""
    <%= if @face == :down or @card == nil do %>
      <div class={card_back_classes(@size)} />
    <% else %>
      <% {suit, rank} = @card %>
      <% color_class = if Cards.suit_color(suit) == :red, do: "text-card-red", else: "text-card-black" %>
      <div
        class={card_face_classes(@size, @clickable, @selected, @dimmed)}
        {if @click_event, do: [{"phx-click", @click_event}, {"phx-value-card", @click_value}], else: []}
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
    base = "relative rounded-lg border border-stone-300 bg-card-cream shadow-sm select-none"

    size_class = if size == :small, do: "w-[50px] h-[72px]", else: "w-[70px] h-[100px]"

    click_class =
      if clickable and not dimmed, do: "cursor-pointer hover:scale-105 hover:shadow-md", else: ""

    selected_class =
      if selected,
        do: "-translate-y-2 ring-2 ring-blue-400 shadow-lg shadow-blue-400/30",
        else: ""

    dimmed_class = if dimmed, do: "opacity-40 cursor-default", else: ""

    [base, size_class, click_class, selected_class, dimmed_class]
    |> Enum.filter(&(&1 != ""))
    |> Enum.join(" ")
  end

  defp card_back_classes(size) do
    size_class = if size == :small, do: "w-[50px] h-[72px]", else: "w-[70px] h-[100px]"

    "#{size_class} rounded-lg border-2 border-card-back-border bg-card-back select-none card-back-pattern"
  end

  defp rank_class(:small), do: "text-[10px] font-bold"
  defp rank_class(_), do: "text-xs font-bold"

  defp suit_small_class(:small), do: "text-[9px] -mt-0.5"
  defp suit_small_class(_), do: "text-[10px] -mt-0.5"

  defp suit_center_class(:small), do: "text-xl"
  defp suit_center_class(_), do: "text-2xl"
end
