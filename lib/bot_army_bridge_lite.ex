defmodule BotArmyBridgeLite do
  @moduledoc """
  Minimal NATS facade for the core bot pack.

  Subscribes to bridge.task.*, bridge.project.*, and bridge.world.snapshot
  subjects and forwards to downstream bots via request/reply.

  No session management, no RPG dependency, no registry calls.
  Connection-only discovery — degrades gracefully when bots are absent.
  """

  @version Mix.Project.config()[:version]

  def version, do: @version
end
