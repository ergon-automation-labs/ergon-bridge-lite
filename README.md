# bot_army_bridge_lite

Minimal NATS facade for the core bot pack. Subscribes to
`bridge.task.*`, `bridge.project.*` and `bridge.world.snapshot`
subjects and forwards to downstream bots via request/reply.

No session management, no RPG dependency, no registry calls.
Connection-only discovery — degrades gracefully when bots are absent.

## Subjects

| Subject | Direction | Purpose |
| --- | --- | --- |
| `bridge.task.*` | subscribe | task bridging to downstream bots |
| `bridge.project.*` | subscribe | project bridging |
| `bridge.world.snapshot` | subscribe | world snapshot requests |
| `bridge.logs.search` | request | LogSearch over fleet log files (flat + `root/*/base` resolution) |

Replies are written back on the request's reply subject via the raw
`Gnat` connection (`GenServer.call(Connection, :get_connection)`) —
reply bodies are JSON-encoded maps.

## Development

```sh
mix deps.get
mix test
make publish-release
```

`config/runtime.exs` reads `NATS_HOST` / `NATS_PORT` at boot via
`ConfigLoader` so releases never bake in the dev broker.