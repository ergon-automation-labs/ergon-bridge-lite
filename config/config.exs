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

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

env_config = Path.join(__DIR__, "#{config_env()}.exs")

if File.exists?(env_config) do
  import_config "#{config_env()}.exs"
end
