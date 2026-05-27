defmodule BotArmyBridgeLite.Application do
  @moduledoc """
  Bridge Lite application supervisor.

  Starts NATS connection (via bot_army_library_runtime), the bridge consumer,
  health responder, and pulse publisher.
  """

  use Application

  @env Mix.env()
  @version Mix.Project.config()[:version]

  @impl true
  def start(_type, _args) do
    children =
      if @env == :test do
        []
      else
        [
          {BotArmyBridgeLite.BridgeConsumer, []}
        ] ++ maybe_add_health_responder() ++ [{BotArmyBridgeLite.PulsePublisher, []}]
      end

    opts = [strategy: :one_for_one, name: BotArmyBridgeLite.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_health_responder do
    if Application.get_env(:bot_army_library_runtime, :pack_mode, false),
      do: [],
      else: [
        {BotArmyRuntime.Health.Responder,
         [
           bot_name: :bridge_lite,
           version: @version,
           process_names: [BotArmyBridgeLite.BridgeConsumer]
         ]}
      ]
  end
end
