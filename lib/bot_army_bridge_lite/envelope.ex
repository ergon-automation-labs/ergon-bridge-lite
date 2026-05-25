defmodule BotArmyBridgeLite.Envelope do
  @moduledoc """
  Builds the standard Bot Army NATS envelope for GTD write operations.

  Replaces the inline gtd_request/2 pattern from the full bridge.
  """

  @doc """
  Wrap a payload in the standard envelope format expected by GTD bot write handlers.

  ## Fields

    - `event` — the downstream NATS subject (e.g. "gtd.task.create")
    - `event_id` — unique UUID for tracing
    - `timestamp` — ISO8601 UTC timestamp
    - `source` — always "bridge_lite"
    - `source_node` — Erlang node name
    - `triggered_by` — always "user"
    - `schema_version` — always "1.0"
    - `tenant_id` — from env or default
    - `user_id` — from env or default
    - `payload` — the actual request data
  """
  def wrap(event, payload) do
    %{
      "event" => event,
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bridge_lite",
      "source_node" => node() |> Atom.to_string(),
      "triggered_by" => "user",
      "schema_version" => "1.0",
      "tenant_id" => tenant_id(),
      "user_id" => user_id(),
      "payload" => payload
    }
  end

  defp tenant_id,
    do: System.get_env("BOT_ARMY_TENANT_ID", "00000000-0000-0000-0000-000000000001")

  defp user_id,
    do: System.get_env("BOT_ARMY_USER_ID", "00000000-0000-0000-0000-000000000002")
end
