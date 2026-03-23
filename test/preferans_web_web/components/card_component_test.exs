defmodule PreferansWebWeb.CardComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import PreferansWebWeb.CardComponent

  test "renders face-up card with rank and suit" do
    html =
      render_component(&card/1,
        card: {:herc, :ace},
        face: :up,
        clickable: false,
        selected: false,
        dimmed: false,
        size: :normal,
        click_event: nil,
        click_value: nil
      )

    assert html =~ "A"
    assert html =~ "♥"
  end

  test "renders face-down card without card info" do
    html =
      render_component(&card/1,
        card: nil,
        face: :down,
        clickable: false,
        selected: false,
        dimmed: false,
        size: :normal,
        click_event: nil,
        click_value: nil
      )

    assert html =~ "card-back-pattern"
    refute html =~ "♥"
    refute html =~ "♠"
  end

  test "renders small card with smaller dimensions" do
    html =
      render_component(&card/1,
        card: {:pik, :king},
        face: :up,
        clickable: false,
        selected: false,
        dimmed: false,
        size: :small,
        click_event: nil,
        click_value: nil
      )

    assert html =~ "w-[60px]"
    assert html =~ "K"
    assert html =~ "♠"
  end
end
