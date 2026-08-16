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
  format: "[$time] [$level] $message\n",
  metadata: [:correlation_id]

# config/{env}.exs (test.exs, dev.exs, etc.) was never imported, so any
# override it defined (most commonly a *_test database name) was dead code —
# every mix invocation used the settings above unmodified, regardless of
# MIX_ENV. Guarded by File.exists? since not every env has its own file here.
env_config = "#{config_env()}.exs"

if File.exists?(Path.join(__DIR__, env_config)) do
  import_config env_config
end

