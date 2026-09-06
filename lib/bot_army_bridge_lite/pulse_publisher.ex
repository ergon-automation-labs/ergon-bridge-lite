defmodule BotArmyBridgeLite.PulsePublisher do
  @moduledoc """
  Periodic health pulse published to NATS.

  Emits `bot.bridge_lite.pulse` every 30 seconds so fleet monitors
  can detect when bridge_lite is alive.
  """

  use GenServer

  require Logger

  @pulse_interval_ms 30_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_pulse()
    {:ok, %{started_at: System.monotonic_time(:second)}}
  end

  @impl true
  def handle_info(:pulse, state) do
    # P10 (2026-09-06, Docker fleet test): SynapseHealth.publish/1 only accepts a
    # keyword list (publish(opts) when is_list(opts)) — passing a map crashed
    # this GenServer with a FunctionClauseError every 30s (crash-restart loop,
    # ~2 800 errors/day). Call the documented API. :version is not part of the
    # SynapseHealth payload schema — dropped.
    BotArmyLibraryRuntime.SynapseHealth.publish(
      source: "bot_army_bridge_lite",
      service: "bridge_lite",
      health_signal: "nominal",
      uptime_seconds: System.monotonic_time(:second) - state.started_at
    )

    schedule_pulse()
    {:noreply, state}
  end

  defp schedule_pulse do
    Process.send_after(self(), :pulse, @pulse_interval_ms)
  end
end
