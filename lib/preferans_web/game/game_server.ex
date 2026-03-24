defmodule PreferansWeb.Game.GameServer do
  @moduledoc """
  GenServer managing one active Preferans game.
  Communicates with the C++ preferans_server via Erlang Port.
  AI is handled by the C++ engine — no scheduling needed here.
  """

  use GenServer

  require Logger

  alias PreferansWeb.Engine.{CppEngine, CppTranslator}
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

  def deal_next_hand(game_id) do
    GenServer.call(via(game_id), :deal_next_hand)
  catch
    :exit, _ -> {:error, :not_found}
  end

  def get_debug_state(game_id, seat) do
    GenServer.call(via(game_id), {:get_debug_state, seat})
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
    binary_path =
      Application.get_env(:preferans_web, :cpp_engine_path, "./priv/bin/preferans_server")

    model_dir = Application.get_env(:preferans_web, :cpp_model_dir)

    port = CppEngine.open_port(binary_path, model_dir: model_dir)

    players_config =
      Enum.map(init_arg.players, fn p ->
        %{type: if(p.is_ai, do: "ai", else: "human")}
      end)

    new_game_opts = %{
      players: players_config,
      dealer: init_arg[:current_dealer] || 0,
      starting_bule: init_arg[:starting_bule] || [100, 100, 100],
      refes: init_arg[:refe_counts] || [0, 0, 0],
      max_refes: init_arg[:max_refes] || 2
    }

    new_game_opts =
      if init_arg[:seed], do: Map.put(new_game_opts, :seed, init_arg[:seed]), else: new_game_opts

    response = CppEngine.new_game(port, new_game_opts)

    case response do
      %{"status" => "ok", "state" => cpp_state} = resp ->
        parsed_events = CppTranslator.parse_events(resp["events"])

        state = %{
          game_id: init_arg.game_id,
          players: init_arg.players,
          port: port,
          cpp_state: cpp_state,
          bid_history: CppTranslator.extract_bid_history(parsed_events),
          defense_responses: CppTranslator.extract_defense_responses(parsed_events),
          defenders: CppTranslator.extract_defenders(parsed_events),
          all_events: parsed_events,
          match_bule: init_arg[:starting_bule] || [100, 100, 100],
          match_refe_counts: init_arg[:refe_counts] || [0, 0, 0],
          match_supe_ledger: %{},
          hands_played: 0,
          current_dealer: init_arg[:current_dealer] || 0,
          match_id: init_arg[:match_id] || init_arg.game_id,
          max_refes: init_arg[:max_refes] || 2
        }

        {:ok, state}

      %{"status" => "error", "message" => msg} ->
        Logger.error("GameServer: C++ engine new_game failed: #{msg}")
        {:stop, {:engine_error, msg}}
    end
  end

  @impl true
  def handle_call({:get_player_view, seat}, _from, state) do
    view = build_view(state, seat)
    {:reply, {:ok, view}, state}
  end

  @impl true
  def handle_call({:get_debug_state, seat}, _from, state) do
    debug = %{
      seat: seat,
      cpp_state: state.cpp_state,
      all_events: state.all_events,
      bid_history: state.bid_history,
      defense_responses: state.defense_responses,
      defenders: state.defenders,
      match_bule: state.match_bule,
      match_refe_counts: state.match_refe_counts,
      match_supe_ledger: state.match_supe_ledger,
      hands_played: state.hands_played,
      current_dealer: state.current_dealer,
      max_refes: state.max_refes,
      players: Enum.map(state.players, &Map.take(&1, [:seat, :display_name, :is_ai]))
    }

    {:reply, {:ok, debug}, state}
  end

  @impl true
  def handle_call({:submit_action, seat, action}, _from, state) do
    player = Enum.find(state.players, &(&1.seat == seat))
    current = state.cpp_state["current_player"]

    cond do
      player == nil ->
        {:reply, {:error, :invalid_seat}, state}

      player.is_ai ->
        {:reply, {:error, :ai_player}, state}

      current != seat ->
        {:reply, {:error, :not_your_turn}, state}

      true ->
        cpp_action = CppTranslator.action_to_cpp(action)
        response = CppEngine.submit_action(state.port, cpp_action)

        case response do
          %{"status" => "ok", "state" => new_cpp_state} = resp ->
            parsed_events = CppTranslator.parse_events(resp["events"])
            state = process_response(state, new_cpp_state, parsed_events)

            broadcast(state.game_id, {:action_played, state.game_id, seat, action})
            broadcast(state.game_id, {:game_state_updated, state.game_id})

            state = maybe_handle_hand_over(state)

            {:reply, :ok, state}

          %{"status" => "error", "message" => msg} ->
            {:reply, {:error, msg}, state}
        end
    end
  end

  @impl true
  def handle_call(:deal_next_hand, _from, state) do
    if state.cpp_state["phase"] == "hand_over" do
      # Dealer rotates counter-clockwise: (dealer + 1) % 3, matching engine convention
      new_dealer = rem(state.current_dealer + 1, 3)

      players_config =
        Enum.map(state.players, fn p ->
          %{type: if(p.is_ai, do: "ai", else: "human")}
        end)

      response =
        CppEngine.new_game(state.port, %{
          players: players_config,
          dealer: new_dealer,
          starting_bule: state.match_bule,
          refes: state.match_refe_counts,
          max_refes: state.max_refes
        })

      case response do
        %{"status" => "ok", "state" => new_cpp_state} = resp ->
          parsed_events = CppTranslator.parse_events(resp["events"])

          state = %{
            state
            | cpp_state: new_cpp_state,
              current_dealer: new_dealer,
              bid_history: CppTranslator.extract_bid_history(parsed_events),
              defense_responses: %{},
              defenders: [],
              all_events: parsed_events
          }

          broadcast(state.game_id, {:new_hand_starting, state.game_id})
          broadcast(state.game_id, {:game_state_updated, state.game_id})

          {:reply, :ok, state}

        %{"status" => "error", "message" => msg} ->
          {:reply, {:error, msg}, state}
      end
    else
      {:reply, {:error, :not_in_hand_over}, state}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    Logger.error("GameServer: C++ engine exited with status #{code}")
    {:stop, {:engine_crashed, code}, state}
  end

  @impl true
  def handle_info({port, {:data, _data}}, %{port: port} = state) do
    # Unexpected data from port (e.g., stderr) — ignore
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state[:port] do
      CppEngine.close(state.port)
    end
  end

  ## Internal helpers

  defp build_view(state, seat) do
    display_names =
      for p <- state.players, into: %{} do
        {p.seat, p.display_name}
      end

    extras = %{
      bid_history: state.bid_history,
      defense_responses: state.defense_responses,
      defenders: state.defenders
    }

    view = CppTranslator.translate_state(state.cpp_state, seat, extras)

    enriched_players =
      Enum.map(state.players, fn p ->
        engine_player = Enum.find(view.players, &(&1.seat == p.seat)) || %{}
        Map.merge(p, engine_player)
      end)

    Map.merge(view, %{
      display_names: display_names,
      players: enriched_players,
      hands_played: state.hands_played,
      match_bule: state.match_bule,
      match_refe_counts: state.match_refe_counts,
      match_supe_ledger: state.match_supe_ledger
    })
  end

  defp process_response(state, new_cpp_state, parsed_events) do
    new_bid_history =
      state.bid_history ++ CppTranslator.extract_bid_history(parsed_events)

    new_defense_responses =
      Map.merge(
        state.defense_responses,
        CppTranslator.extract_defense_responses(parsed_events)
      )

    new_defenders =
      Enum.uniq(state.defenders ++ CppTranslator.extract_defenders(parsed_events))

    %{
      state
      | cpp_state: new_cpp_state,
        bid_history: new_bid_history,
        defense_responses: new_defense_responses,
        defenders: new_defenders,
        all_events: state.all_events ++ parsed_events
    }
  end

  defp maybe_handle_hand_over(state) do
    if state.cpp_state["phase"] == "hand_over" do
      result = state.cpp_state["result"]

      if result do
        scoring_result = CppTranslator.translate_result(result)
        state = apply_scoring(state, scoring_result)

        broadcast(
          state.game_id,
          {:hand_completed, state.game_id, scoring_result}
        )

        if match_over?(state) do
          broadcast(state.game_id, {:match_ended, state.game_id, final_scores(state)})
        end

        state
      else
        state
      end
    else
      state
    end
  end

  defp apply_scoring(state, scoring_result) do
    new_bule =
      Enum.zip(state.match_bule, scoring_result.bule_changes)
      |> Enum.map(fn {b, c} -> b + c end)

    new_refe =
      cond do
        scoring_result.all_passed and scoring_result.refe_recorded ->
          # All passed — increment refe for each player
          Enum.map(state.match_refe_counts, &(&1 + 1))

        scoring_result.refe_consumed ->
          # A refe was consumed by the declarer
          state.match_refe_counts

        true ->
          state.match_refe_counts
      end

    new_supe =
      Enum.reduce(scoring_result.supe_changes, state.match_supe_ledger, fn {key, amount},
                                                                           ledger ->
        Map.update(ledger, key, amount, &(&1 + amount))
      end)

    %{
      state
      | match_bule: new_bule,
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

  defp broadcast(game_id, message) do
    PubSub.broadcast(@pubsub, topic(game_id), message)
  end
end
