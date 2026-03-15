defmodule PreferansWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PreferansWebWeb.Telemetry,
      PreferansWeb.Repo,
      {DNSCluster, query: Application.get_env(:preferans_web, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PreferansWeb.PubSub},
      # Start a worker by calling: PreferansWeb.Worker.start_link(arg)
      # {PreferansWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      PreferansWebWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PreferansWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PreferansWebWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
