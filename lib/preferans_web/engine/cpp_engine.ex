defmodule PreferansWeb.Engine.CppEngine do
  @moduledoc """
  Port-based communication with the C++ preferans_server binary.

  The C++ server reads JSON commands from stdin (one per line) and writes
  JSON responses to stdout (one per line). AI players are handled internally
  by the C++ server — all AI actions are returned in the events array.

  This module is not a GenServer. The calling process (GameServer) owns the Port.
  """

  require Logger

  @default_timeout 10_000

  def open_port(binary_path, opts \\ []) do
    unless File.exists?(binary_path) do
      raise "C++ engine binary not found at #{binary_path}"
    end

    args =
      case opts[:model_dir] do
        nil -> []
        dir -> ["--model-dir", dir]
      end

    Port.open(
      {:spawn_executable, binary_path},
      [:binary, :exit_status, {:line, 65_536}, :use_stdio, {:args, args}]
    )
  end

  def new_game(port, opts) do
    players =
      Enum.map(opts[:players] || default_players(), fn p ->
        %{"type" => p.type}
      end)

    cmd = %{
      "cmd" => "new_game",
      "players" => players,
      "dealer" => opts[:dealer] || 0,
      "starting_bule" => opts[:starting_bule] || [100, 100, 100],
      "refes" => opts[:refes] || [0, 0, 0],
      "max_refes" => opts[:max_refes] || 2
    }

    seed = opts[:seed] || :rand.uniform(1_000_000_000)
    cmd = Map.put(cmd, "seed", seed)

    send_and_receive(port, cmd)
  end

  def submit_action(port, action_map) do
    send_and_receive(port, %{"cmd" => "action", "action" => action_map})
  end

  def get_state(port) do
    send_and_receive(port, %{"cmd" => "get_state"})
  end

  def close(port) do
    try do
      Port.command(port, Jason.encode!(%{"cmd" => "quit"}) <> "\n")
    catch
      _, _ -> :ok
    end

    try do
      Port.close(port)
    catch
      _, _ -> :ok
    end

    :ok
  end

  defp send_and_receive(port, command, timeout \\ @default_timeout) do
    json = Jason.encode!(command) <> "\n"
    Port.command(port, json)

    receive do
      {^port, {:data, {:eol, line}}} ->
        case Jason.decode(line) do
          {:ok, response} ->
            response

          {:error, reason} ->
            Logger.error("CppEngine: failed to decode JSON response: #{inspect(reason)}")
            %{"status" => "error", "message" => "Invalid JSON from engine"}
        end

      {^port, {:exit_status, code}} ->
        Logger.error("CppEngine: process exited with status #{code}")
        %{"status" => "error", "message" => "Engine process exited (code #{code})"}
    after
      timeout ->
        Logger.error("CppEngine: timeout waiting for response")
        %{"status" => "error", "message" => "Engine timeout"}
    end
  end

  defp default_players do
    [
      %{type: "human"},
      %{type: "ai"},
      %{type: "ai"}
    ]
  end
end
