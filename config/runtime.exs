import Config

config :bot_army_library_runtime, :auto_start_services, true

nats_servers =
  case System.get_env("NATS_SERVERS") do
    nil ->
      nats_host = System.get_env("NATS_HOST", "nats")
      nats_port = System.get_env("NATS_PORT", "4222") |> String.to_integer()
      [{nats_host, nats_port}]

    servers_string ->
      servers_string
      |> String.split()
      |> Enum.map(fn server_spec ->
        case String.split(server_spec, ":") do
          [host, port_str] -> {host, String.to_integer(port_str)}
          [host] -> {host, 4222}
          _ -> {"nats", 4222}
        end
      end)
  end

config :bot_army_library_runtime, :nats,
  servers: nats_servers,
  ping_interval: 30_000

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
