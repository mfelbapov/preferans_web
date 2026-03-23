defmodule PreferansWebWeb.GameLiveTest do
  use PreferansWebWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PreferansWeb.Game
  alias PreferansWeb.Game.GameServer

  setup :register_and_log_in_user

  defp start_game(%{user: user}) do
    # Use seed 42: both AIs pass in bidding, giving human the chance to bid
    {:ok, game_id} = Game.start_solo_game(user.id, seed: 42)
    %{game_id: game_id}
  end

  describe "mount" do
    test "redirects to lobby for invalid game_id", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/lobby"}}} = live(conn, ~p"/game/99999999")
    end

    test "renders game for valid game_id", %{conn: conn} = ctx do
      %{game_id: game_id} = start_game(ctx)
      {:ok, _lv, html} = live(conn, ~p"/game/#{game_id}")

      assert html =~ "game-container"
    end
  end

  describe "bidding" do
    setup :start_game

    test "shows bidding UI", %{conn: conn, game_id: game_id} do
      {:ok, _lv, html} = live(conn, ~p"/game/#{game_id}")

      # Should show either bidding UI or waiting message
      assert html =~ "Pass" or html =~ "Waiting"
    end
  end

  describe "discard phase — card selection" do
    setup ctx do
      %{game_id: game_id} = start_game(ctx)

      # Advance to discard phase by submitting bids directly (avoids AI timing)
      advance_to_discard(game_id)

      %{game_id: game_id}
    end

    test "clicking cards toggles selection and confirm button appears", %{
      conn: conn,
      game_id: game_id
    } do
      {:ok, lv, _html} = live(conn, ~p"/game/#{game_id}")
      render(lv)

      {:ok, view} = GameServer.get_player_view(game_id, 0)
      assert view.phase == :discard
      hand = view.my_hand
      assert length(hand) == 12

      card1 = Enum.at(hand, 0)
      card2 = Enum.at(hand, 1)

      # Click first card — should get selected (ring-2 class)
      html = lv |> element("#discard-#{card_dom_id(card1)}") |> render_click()
      assert html =~ "ring-2"

      # Click second card — confirm button should appear
      lv |> element("#discard-#{card_dom_id(card2)}") |> render_click()
      assert has_element?(lv, "#confirm-discard-btn")

      # Click confirm — should transition to declare_game
      lv |> element("#confirm-discard-btn") |> render_click()

      wait_for_phase(lv, game_id, :declare_game)
      {:ok, view} = GameServer.get_player_view(game_id, 0)
      assert view.phase == :declare_game
      assert length(view.my_hand) == 10
    end

    test "deselecting a card works", %{conn: conn, game_id: game_id} do
      {:ok, lv, _html} = live(conn, ~p"/game/#{game_id}")
      render(lv)

      {:ok, view} = GameServer.get_player_view(game_id, 0)
      card1 = Enum.at(view.my_hand, 0)

      # Select card
      lv |> element("#discard-#{card_dom_id(card1)}") |> render_click()
      assert render(lv) =~ "ring-2"

      # Deselect same card
      lv |> element("#discard-#{card_dom_id(card1)}") |> render_click()
      refute has_element?(lv, "#confirm-discard-btn")
    end
  end

  describe "card component" do
    test "renders in game view", %{conn: conn} = ctx do
      %{game_id: game_id} = start_game(ctx)
      {:ok, _lv, html} = live(conn, ~p"/game/#{game_id}")

      # Cards should be rendered (suit symbols)
      assert html =~ "♠" or html =~ "♦" or html =~ "♥" or html =~ "♣"
    end
  end

  describe "scoring sidebar" do
    test "shows bule values", %{conn: conn} = ctx do
      %{game_id: game_id} = start_game(ctx)
      {:ok, _lv, html} = live(conn, ~p"/game/#{game_id}")

      assert html =~ "Bule"
      assert html =~ "100"
    end
  end

  ## Helpers

  defp advance_to_discard(game_id) do
    # With the C++ engine, we need to actually play through bidding.
    # Wait for it to be seat 0's turn, then bid to reach discard.
    wait_for_turn(game_id, 0, 50)

    {:ok, view} = GameServer.get_player_view(game_id, 0)

    case view.phase do
      :bid ->
        # Find the lowest available bid and use it
        bid_action =
          Enum.find(view.legal_actions, fn
            {:bid, _} -> true
            _ -> false
          end)

        if bid_action do
          :ok = GameServer.submit_action(game_id, 0, bid_action)
          # Wait for discard phase (AI may auto-pass, leading to discard)
          wait_for_phase_server(game_id, :discard, 50)
        else
          # No bid available, just pass — game may go to hand_over (all passed)
          :ok = GameServer.submit_action(game_id, 0, :dalje)
          wait_for_phase_server(game_id, :discard, 50)
        end

      :discard ->
        :ok
    end
  end

  defp wait_for_turn(game_id, seat, retries) when retries > 0 do
    {:ok, view} = GameServer.get_player_view(game_id, seat)

    if view.is_my_turn do
      :ok
    else
      Process.sleep(100)
      wait_for_turn(game_id, seat, retries - 1)
    end
  end

  defp wait_for_turn(_, _, 0), do: :timeout

  defp wait_for_phase_server(game_id, phase, retries) when retries > 0 do
    {:ok, view} = GameServer.get_player_view(game_id, 0)

    if view.phase == phase do
      :ok
    else
      Process.sleep(100)
      wait_for_phase_server(game_id, phase, retries - 1)
    end
  end

  defp wait_for_phase_server(_, _, 0), do: :timeout

  defp card_dom_id({suit, rank}), do: "#{suit}-#{rank}"

  defp wait_for_phase(lv, game_id, phase, retries \\ 50) do
    {:ok, view} = GameServer.get_player_view(game_id, 0)

    if view.phase == phase do
      render(lv)
      :ok
    else
      if retries <= 0 do
        flunk("Timed out waiting for phase #{phase}, current: #{view.phase}")
      end

      Process.sleep(300)
      render(lv)
      wait_for_phase(lv, game_id, phase, retries - 1)
    end
  end
end
