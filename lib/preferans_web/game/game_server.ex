defmodule PreferansWeb.Game.GameServer do
  @moduledoc """
  GenServer managing one active Preferans game.
  Uses MockEngine now, swappable to C++ engine later.
  """

  use GenServer

  alias PreferansWeb.Game.{Cards, MockEngine}
  alias Phoenix.PubSub

  @pubsub PreferansWeb.PubSub

  ## Public API

  def start_link(init_arg) do
    game_id = init_arg.game_id
    GenServer.start_link(__MODULE__, init_arg, name: via(game_id))
  end

  def get_player_view(game_id, seat) do
    GenServer.call(via(game_id), {:get_player_view, seat})
  catch
    :exit, _ -> {:error, :not_found}
  end

  def submit_action(game_id, seat, action) do
    GenServer.call(via(game_id), {:submit_action, seat, action})
  catch
    :exit, _ -> {:error, :not_found}
  end

  def subscribe(game_id) do
    PubSub.subscribe(@pubsub, topic(game_id))
  end

  def game_exists?(game_id) do
    case Registry.lookup(PreferansWeb.GameRegistry, game_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  defp via(game_id) do
    {:via, Registry, {PreferansWeb.GameRegistry, game_id}}
  end

  defp topic(game_id), do: "game:#{game_id}"

  ## GenServer callbacks

  @impl true
  def init(init_arg) do
    engine_state =
      MockEngine.new_hand(
        init_arg[:current_dealer] || 0,
        init_arg[:starting_bule] || [100, 100, 100],
        init_arg[:refe_counts] || [0, 0, 0],
        init_arg[:max_refes] || 2
      )

    state = %{
      game_id: init_arg.game_id,
      players: init_arg.players,
      engine_state: engine_state,
      match_bule: init_arg[:starting_bule] || [100, 100, 100],
      match_refe_counts: init_arg[:refe_counts] || [0, 0, 0],
      match_supe_ledger: %{},
      hands_played: 0,
      current_dealer: init_arg[:current_dealer] || 0,
      match_id: init_arg[:match_id] || init_arg.game_id,
      max_refes: init_arg[:max_refes] || 2
    }

    # Schedule AI turn if first player is AI
    state = maybe_schedule_ai_turn(state)

    {:ok, state}
  end

  @impl true
  def handle_call({:get_player_view, seat}, _from, state) do
    view = MockEngine.get_player_view(state.engine_state, seat)

    display_names =
      for p <- state.players, into: %{} do
        {p.seat, p.display_name}
      end

    view =
      Map.merge(view, %{
        display_names: display_names,
        hands_played: state.hands_played,
        match_bule: state.match_bule,
        match_refe_counts: state.match_refe_counts,
        match_supe_ledger: state.match_supe_ledger
      })

    {:reply, {:ok, view}, state}
  end

  @impl true
  def handle_call({:submit_action, seat, action}, _from, state) do
    player = Enum.find(state.players, &(&1.seat == seat))

    cond do
      player == nil ->
        {:reply, {:error, :invalid_seat}, state}

      player.is_ai ->
        {:reply, {:error, :ai_player}, state}

      state.engine_state.current_player != seat ->
        {:reply, {:error, :not_your_turn}, state}

      true ->
        case MockEngine.apply_action(state.engine_state, action) do
          {:ok, new_engine_state} ->
            state = %{state | engine_state: new_engine_state}
            broadcast(state.game_id, {:action_played, state.game_id, seat, action})
            broadcast(state.game_id, {:game_state_updated, state.game_id})

            state = handle_phase_transitions(state)
            state = maybe_schedule_ai_turn(state)

            {:reply, :ok, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_info({:ai_turn, seat}, state) do
    # Verify it's still this AI's turn
    if state.engine_state.current_player == seat and
         state.engine_state.phase not in [:hand_over, :scoring] do
      action = pick_ai_action(state)

      case MockEngine.apply_action(state.engine_state, action) do
        {:ok, new_engine_state} ->
          state = %{state | engine_state: new_engine_state}
          broadcast(state.game_id, {:action_played, state.game_id, seat, action})
          broadcast(state.game_id, {:game_state_updated, state.game_id})

          state = handle_phase_transitions(state)
          state = maybe_schedule_ai_turn(state)

          {:noreply, state}

        {:error, _reason} ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:deal_next_hand, state) do
    new_dealer = rem(state.current_dealer + 1, 3)

    engine_state =
      MockEngine.new_hand(
        new_dealer,
        state.match_bule,
        state.match_refe_counts,
        state.max_refes
      )

    state = %{state | engine_state: engine_state, current_dealer: new_dealer}
    broadcast(state.game_id, {:new_hand_starting, state.game_id})
    broadcast(state.game_id, {:game_state_updated, state.game_id})

    state = maybe_schedule_ai_turn(state)

    {:noreply, state}
  end

  ## Internal

  defp handle_phase_transitions(state) do
    cond do
      state.engine_state.phase == :scoring ->
        # Auto-transition scoring → hand_over
        state = apply_scoring(state)

        broadcast(
          state.game_id,
          {:hand_completed, state.game_id, state.engine_state.scoring_result}
        )

        if match_over?(state) do
          broadcast(state.game_id, {:match_ended, state.game_id, final_scores(state)})
          state
        else
          Process.send_after(self(), :deal_next_hand, 4000)
          state
        end

      true ->
        state
    end
  end

  defp apply_scoring(state) do
    result = state.engine_state.scoring_result

    new_bule =
      Enum.zip(state.match_bule, result.bule_changes)
      |> Enum.map(fn {b, c} -> b + c end)

    new_refe =
      if result.all_passed do
        state.engine_state.refe_counts
      else
        state.match_refe_counts
      end

    new_supe =
      Enum.reduce(result.supe_changes, state.match_supe_ledger, fn change, ledger ->
        key = {change.from, change.to}
        Map.update(ledger, key, change.amount, &(&1 + change.amount))
      end)

    engine_state = %{state.engine_state | phase: :hand_over}

    %{
      state
      | engine_state: engine_state,
        match_bule: new_bule,
        match_refe_counts: new_refe,
        match_supe_ledger: new_supe,
        hands_played: state.hands_played + 1
    }
  end

  defp match_over?(state) do
    Enum.any?(state.match_bule, &(&1 <= 0))
  end

  defp final_scores(state) do
    %{
      bule: state.match_bule,
      refe_counts: state.match_refe_counts,
      supe_ledger: state.match_supe_ledger,
      hands_played: state.hands_played
    }
  end

  defp maybe_schedule_ai_turn(state) do
    seat = state.engine_state.current_player
    player = Enum.find(state.players, &(&1.seat == seat))

    if player && player.is_ai && state.engine_state.phase not in [:hand_over, :scoring] do
      Process.send_after(self(), {:ai_turn, seat}, ai_delay(state))
    end

    state
  end

  defp ai_delay(state) do
    case state.engine_state.phase do
      :bid -> Enum.random(600..1200)
      :defense -> Enum.random(800..1500)
      :trick_play -> Enum.random(500..1000)
      _ -> 500
    end
  end

  defp pick_ai_action(state) do
    legal = MockEngine.get_legal_actions(state.engine_state)

    case state.engine_state.phase do
      :bid ->
        # 70% pass, 20% bid lowest, 10% bid one higher
        r = :rand.uniform(100)

        cond do
          r <= 70 -> :dalje
          r <= 90 -> Enum.find(legal, :dalje, &match?({:bid, _}, &1))
          true -> Enum.reverse(legal) |> Enum.find(:dalje, &match?({:bid, _}, &1))
        end

      :defense ->
        if :rand.uniform(100) <= 60, do: :dodjem, else: :ne_dodjem

      :trick_play ->
        # Play lowest legal card
        legal
        |> Enum.sort_by(fn {:play, {_s, r}} -> Cards.rank_value(r) end)
        |> hd()

      :discard ->
        Enum.random(legal)

      :declare_game ->
        # Pick game matching highest bid value
        hd(legal)

      _ ->
        hd(legal)
    end
  end

  defp broadcast(game_id, message) do
    PubSub.broadcast(@pubsub, topic(game_id), message)
  end
end
