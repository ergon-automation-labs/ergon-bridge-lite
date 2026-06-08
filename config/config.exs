import Config

config :bot_army_bridge_lite, :deployment_status, "experimental"

config :bot_army_bridge_lite,
  bridge_subjects: [
    "bridge.task.create",
    "bridge.task.list",
    "bridge.task.get",
    "bridge.task.search",
    "bridge.task.update",
    "bridge.task.complete",
    "bridge.project.create",
    "bridge.project.list",
    "bridge.project.update",
    "bridge.world.snapshot"
  ]

config :bot_army_library_runtime, :nats, servers: [{"localhost", 4223}]

config :logger,
  level: :info,
  backends: [:console]

config :logger, :console,
  format: {BotArmyRuntime.LoggerFormatter, []},
  metadata: [:correlation_id]
