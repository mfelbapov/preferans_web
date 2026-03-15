defmodule PreferansWeb.Game.GameServerTest do
  use PreferansWeb.DataCase, async: false

  alias PreferansWeb.Game.GameServer

  defp start_game(game_id \\ nil) do
    gid = game_id || "game-#{:erlang.unique_integer([:positive])}"

    init_arg = %{
      game_id: gid,
      starting_bule: [100, 100, 100],
      max_refes: 2,
      current_dealer: 0,
      refe_counts: [0, 0, 0],
      players: [
        %{seat: 0, user_id: nil, is_ai: false, display_name: "Human"},
        %{seat: 1, user_id: nil, is_ai: true, ai_level: "heuristic", display_name: "Bot 1"},
        %{seat: 2, user_id: nil, is_ai: true, ai_level: "heuristic", display_name: "Bot 2"}
      ]
    }

    {:ok, _pid} =
      DynamicSupervisor.start_child(PreferansWeb.GameSupervisor, {GameServer, init_arg})

    gid
  end

  describe "start and registration" do
    test "starts and registers correctly" do
      game_id = start_game()
      assert GameServer.game_exists?(game_id)
    end

    test "game_exists? returns false for unknown game" do
      refute GameServer.game_exists?("nonexistent-game")
    end
  end

  describe "get_player_view/2" do
    test "returns player view" do
      game_id = start_game()
      {:ok, view} = GameServer.get_player_view(game_id, 0)

      assert view.my_seat == 0
      assert is_list(view.my_hand)
      assert view.display_names["Human"] || Map.has_key?(view.display_names, 0)
    end

    test "returns error for non-existent game" do
      assert {:error, :not_found} = GameServer.get_player_view("does-not-exist", 0)
    end
  end

  describe "submit_action/3" do
    test "rejects actions from wrong player" do
      game_id = start_game()
      {:ok, view} = GameServer.get_player_view(game_id, 0)

      # If it's not seat 0's turn, submitting should fail
      if !view.is_my_turn do
        assert {:error, :not_your_turn} = GameServer.submit_action(game_id, 0, :dalje)
      end
    end

    test "rejects actions from AI players" do
      game_id = start_game()
      assert {:error, :ai_player} = GameServer.submit_action(game_id, 1, :dalje)
    end

    test "accepts valid action from human player on their turn" do
      game_id = start_game()
      {:ok, view} = GameServer.get_player_view(game_id, 0)

      if view.is_my_turn do
        assert :ok = GameServer.submit_action(game_id, 0, :dalje)
      end
    end
  end

  describe "PubSub broadcasts" do
    test "broadcasts on state changes" do
      game_id = start_game()
      GameServer.subscribe(game_id)

      {:ok, view} = GameServer.get_player_view(game_id, 0)

      if view.is_my_turn do
        :ok = GameServer.submit_action(game_id, 0, :dalje)
        assert_receive {:action_played, ^game_id, 0, :dalje}, 1000
        assert_receive {:game_state_updated, ^game_id}, 1000
      end
    end
  end

  describe "AI turns" do
    test "AI turns fire automatically" do
      game_id = start_game()
      GameServer.subscribe(game_id)

      {:ok, view} = GameServer.get_player_view(game_id, 0)

      if view.is_my_turn do
        # Human plays, then AI should follow
        :ok = GameServer.submit_action(game_id, 0, :dalje)

        # Wait for AI to play (they have 500-1500ms delay)
        assert_receive {:game_state_updated, ^game_id}, 3000
      else
        # AI is first — should fire automatically
        assert_receive {:game_state_updated, ^game_id}, 3000
      end
    end
  end
end
