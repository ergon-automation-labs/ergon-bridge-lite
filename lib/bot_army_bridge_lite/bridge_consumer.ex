defmodule BotArmyBridgeLite.BridgeConsumer do
  @moduledoc """
  Minimal NATS facade for the core bot pack.

  Subscribes to task, project, and world.snapshot subjects and forwards
  to downstream bots via request/reply. Connection-only discovery — no
  registry dependency. Graceful degradation when downstream bots are absent.
  """

  use GenServer

  require Logger

  alias BotArmyBridgeLite.Envelope
  alias BotArmyRuntime.NATS.Connection
  alias BotArmyRuntime.NATS.Publisher
  alias BotArmyRuntime.NATS.Reply

  @reconnect_delay_ms 5_000
  @request_timeout 5_000

  @subjects [
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

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Logger.info("[BridgeLite] Starting bridge control API")

    state = %{
      subscriptions: [],
      opts: opts
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case GenServer.call(Connection, :get_connection, 5_000) do
      {:ok, conn} ->
        subscriptions =
          for subject <- @subjects do
            {:ok, sid} = Gnat.sub(conn, self(), subject)
            {subject, sid}
          end

        Connection.subscribe_to_status()
        Logger.info("[BridgeLite] Subscribed to #{length(subscriptions)} subjects")
        {:noreply, %{state | subscriptions: subscriptions}}

      {:error, reason} ->
        Logger.warning("[BridgeLite] NATS unavailable, retrying: #{inspect(reason)}")
        Process.send_after(self(), :reconnect, @reconnect_delay_ms)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    handle_bridge_request(msg)
    {:noreply, state}
  end

  @impl true
  def handle_info({:nats, :disconnected}, state) do
    Logger.warning("[BridgeLite] NATS disconnected")
    {:noreply, %{state | subscriptions: []}}
  end

  @impl true
  def handle_info({:nats, :connected}, _state) do
    Logger.info("[BridgeLite] NATS reconnected, re-subscribing")
    {:noreply, %{subscriptions: []}, {:continue, :connect}}
  end

  @impl true
  def handle_info(:reconnect, state) do
    Logger.info("[BridgeLite] Attempting NATS reconnect")
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Task handlers ---

  defp handle_bridge_request(%{topic: "bridge.task.create"} = msg) do
    with {:ok, params} <- decode_json(msg.body),
         title when is_binary(title) and title != "" <- Map.get(params, "title") do
      payload = %{
        "title" => title,
        "description" => Map.get(params, "description"),
        "priority" => Map.get(params, "priority"),
        "context" => Map.get(params, "context"),
        "labels" => Map.get(params, "labels"),
        "project_id" => Map.get(params, "project_id"),
        "goal_id" => Map.get(params, "goal_id")
      }

      payload = Map.reject(payload, fn {_k, v} -> is_nil(v) end)

      case gtd_request("gtd.task.create", payload) do
        {:ok, body} ->
          Logger.info("[BridgeLite] Task created: #{title}")
          reply(msg, body)

        {:error, reason} ->
          reply(msg, Reply.error(inspect(reason), :upstream_error))
      end
    else
      _ -> reply(msg, Reply.error("title required", :validation_error))
    end
  end

  defp handle_bridge_request(%{topic: "bridge.task.list"} = msg) do
    params =
      case decode_json(msg.body) do
        {:ok, p} -> p
        _ -> %{}
      end

    limit = min(Map.get(params, "limit", 50), 500)
    offset = Map.get(params, "offset", 0)

    request_body =
      Jason.encode!(%{
        "tenant_id" => tenant_id(),
        "limit" => limit,
        "offset" => offset,
        "sort" => Map.get(params, "sort"),
        "order" => Map.get(params, "order")
      })

    case nats_request("gtd.task.list", request_body) do
      {:ok, body} ->
        reply(msg, body)

      {:error, reason} ->
        reply(msg, Reply.error(inspect(reason), :upstream_error))
    end
  end

  defp handle_bridge_request(%{topic: "bridge.task.search"} = msg) do
    with {:ok, params} <- decode_json(msg.body),
         query when is_binary(query) and query != "" <- Map.get(params, "query") do
      limit = min(Map.get(params, "limit", 50), 500)
      offset = Map.get(params, "offset", 0)

      request_body =
        Jason.encode!(%{
          "tenant_id" => tenant_id(),
          "query" => query,
          "filters" => Map.get(params, "filters", %{}),
          "pagination" => %{
            "limit" => limit,
            "offset" => offset
          }
        })

      case nats_request("gtd.task.search", request_body) do
        {:ok, body} ->
          Logger.info("[BridgeLite] Task search: query=#{query}")
          reply(msg, body)

        {:error, :no_responders} ->
          fallback_task_search(msg, query, limit, offset)

        {:error, reason} ->
          Logger.warning(
            "[BridgeLite] gtd.task.search unavailable, falling back: #{inspect(reason)}"
          )

          fallback_task_search(msg, query, limit, offset)
      end
    else
      _ -> reply(msg, Reply.error("query required", :validation_error))
    end
  end

  defp handle_bridge_request(%{topic: "bridge.task.get"} = msg) do
    with {:ok, params} <- decode_json(msg.body),
         task_id when is_binary(task_id) and task_id != "" <- Map.get(params, "task_id") do
      request_body = Jason.encode!(%{"tenant_id" => tenant_id(), "task_id" => task_id})

      case nats_request("gtd.task.get", request_body) do
        {:ok, body} ->
          Logger.info("[BridgeLite] Task fetched: #{task_id}")
          reply(msg, body)

        {:error, reason} ->
          reply(msg, Reply.error(inspect(reason), :upstream_error))
      end
    else
      _ -> reply(msg, Reply.error("task_id required", :validation_error))
    end
  end

  defp handle_bridge_request(%{topic: "bridge.task.update"} = msg) do
    with {:ok, params} <- decode_json(msg.body),
         task_id when is_binary(task_id) and task_id != "" <- Map.get(params, "task_id") do
      update_payload = %{
        "task_id" => task_id,
        "title" => Map.get(params, "title"),
        "description" => Map.get(params, "description"),
        "priority" => Map.get(params, "priority"),
        "context" => Map.get(params, "context"),
        "status" => Map.get(params, "status"),
        "due_date" => Map.get(params, "due_date"),
        "active_until" => Map.get(params, "active_until"),
        "labels" => Map.get(params, "labels"),
        "project_id" => Map.get(params, "project_id"),
        "goal_id" => Map.get(params, "goal_id"),
        "parent_task_id" => Map.get(params, "parent_task_id")
      }

      update_payload = Map.reject(update_payload, fn {_k, v} -> is_nil(v) end)

      case gtd_request("gtd.task.update", update_payload) do
        {:ok, body} ->
          Logger.info("[BridgeLite] Task updated: #{task_id}")
          reply(msg, body)

        {:error, reason} ->
          reply(msg, Reply.error(inspect(reason), :upstream_error))
      end
    else
      _ -> reply(msg, Reply.error("task_id required", :validation_error))
    end
  end

  defp handle_bridge_request(%{topic: "bridge.task.complete"} = msg) do
    with {:ok, params} <- decode_json(msg.body),
         task_id when is_binary(task_id) and task_id != "" <- Map.get(params, "task_id") do
      case gtd_request("gtd.task.complete", %{"task_id" => task_id}) do
        {:ok, body} ->
          Logger.info("[BridgeLite] Task completed: #{task_id}")
          reply(msg, body)

        {:error, reason} ->
          reply(msg, Reply.error(inspect(reason), :upstream_error))
      end
    else
      _ -> reply(msg, Reply.error("task_id required", :validation_error))
    end
  end

  # --- Project handlers ---

  defp handle_bridge_request(%{topic: "bridge.project.create"} = msg) do
    with {:ok, params} <- decode_json(msg.body),
         name when is_binary(name) and name != "" <- Map.get(params, "name") do
      case gtd_request("gtd.project.create", %{
             "name" => name,
             "description" => Map.get(params, "description")
           }) do
        {:ok, body} ->
          Logger.info("[BridgeLite] Project created: #{name}")
          reply(msg, body)

        {:error, reason} ->
          reply(msg, Reply.error(inspect(reason), :upstream_error))
      end
    else
      _ -> reply(msg, Reply.error("name required", :validation_error))
    end
  end

  defp handle_bridge_request(%{topic: "bridge.project.list"} = msg) do
    case gtd_request("gtd.project.list", %{}) do
      {:ok, body} ->
        reply(msg, body)

      {:error, reason} ->
        reply(msg, Reply.error(inspect(reason), :upstream_error))
    end
  end

  defp handle_bridge_request(%{topic: "bridge.project.update"} = msg) do
    with {:ok, params} <- decode_json(msg.body),
         "1.0" <- Map.get(params, "schema_version"),
         project_id when is_binary(project_id) and project_id != "" <-
           Map.get(params, "project_id") do
      update_payload =
        %{
          "project_id" => project_id,
          "name" => Map.get(params, "name"),
          "description" => Map.get(params, "description"),
          "status" => Map.get(params, "status"),
          "labels" => Map.get(params, "labels"),
          "area" => Map.get(params, "area"),
          "incident_fingerprint" => Map.get(params, "incident_fingerprint"),
          "verification" => Map.get(params, "verification")
        }
        |> Map.reject(fn {_k, v} -> is_nil(v) end)

      case gtd_request("gtd.project.update", update_payload) do
        {:ok, body} ->
          Logger.info("[BridgeLite] Project updated: #{project_id}")
          reply(msg, body)

        {:error, reason} ->
          reply(msg, Reply.error(inspect(reason), :upstream_error))
      end
    else
      {:error, reason} when is_binary(reason) ->
        reply(msg, Reply.error(reason, :validation_error))

      _ ->
        reply(msg, Reply.error("schema_version 1.0 and project_id required", :validation_error))
    end
  end

  # --- World snapshot handler ---

  defp handle_bridge_request(%{topic: "bridge.world.snapshot"} = msg) do
    case decode_json(msg.body) do
      {:ok, _params} ->
        handle_world_snapshot(msg)

      {:error, _} ->
        reply(msg, Reply.error("invalid JSON", :validation_error))
    end
  end

  defp handle_world_snapshot(msg) do
    # Try fetching tasks and projects concurrently for a degraded snapshot.
    # No RPG dependency — this is connection-only discovery.
    tasks_task =
      Task.async(fn ->
        nats_request(
          "gtd.task.list",
          Jason.encode!(%{"tenant_id" => tenant_id(), "limit" => 10})
        )
      end)

    projects_task =
      Task.async(fn ->
        nats_request("gtd.project.list", Jason.encode!(%{}))
      end)

    tasks_result = Task.await(tasks_task, @request_timeout + 1_000)
    projects_result = Task.await(projects_task, @request_timeout + 1_000)

    recent_tasks =
      case tasks_result do
        {:ok, body} ->
          case Jason.decode(body) do
            {:ok, %{"data" => %{"tasks" => tasks}}} ->
              if is_list(tasks), do: tasks, else: []

            {:ok, %{"data" => tasks}} ->
              if is_list(tasks), do: tasks, else: []

            _ ->
              []
          end

        _ ->
          []
      end

    projects =
      case projects_result do
        {:ok, body} ->
          case Jason.decode(body) do
            {:ok, %{"data" => %{"projects" => projects}}} ->
              if is_list(projects), do: projects, else: []

            {:ok, %{"data" => projects}} ->
              if is_list(projects), do: projects, else: []

            _ ->
              []
          end

        _ ->
          []
      end

    active_bots =
      []
      |> Kernel.++(if tasks_result != {:error, :no_responders}, do: ["gtd"], else: [])
      |> Kernel.++(if projects_result != {:error, :no_responders}, do: ["gtd"], else: [])
      |> Enum.uniq()

    note =
      cond do
        Enum.empty?(active_bots) -> "bridge_lite: no downstream services available"
        true -> "bridge_lite: minimal snapshot (no RPG enrichment)"
      end

    snapshot = %{
      "ok" => true,
      "schema_version" => "1.0",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bridge_lite",
      "theme" => nil,
      "active_bots" => active_bots,
      "recent_tasks" => recent_tasks,
      "projects" => projects,
      "note" => note
    }

    reply(msg, Jason.encode!(snapshot))
  end

  # --- Fallback for task search ---

  defp fallback_task_search(msg, query, limit, offset) do
    request_body =
      Jason.encode!(%{
        "tenant_id" => tenant_id(),
        "limit" => limit,
        "offset" => offset
      })

    case nats_request("gtd.task.list", request_body) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, %{"data" => %{"tasks" => tasks}} = response} when is_list(tasks) ->
            filtered =
              Enum.filter(tasks, fn task ->
                title = Map.get(task, "title", "")
                String.contains?(String.downcase(title), String.downcase(query))
              end)

            reply(msg, Jason.encode!(%{response | "data" => %{"tasks" => filtered}}))

          {:ok, body_decoded} when is_map(body_decoded) ->
            reply(msg, Jason.encode!(body_decoded))

          _ ->
            reply(msg, body)
        end

      {:error, reason} ->
        reply(msg, Reply.error(inspect(reason), :upstream_error))
    end
  end

  # --- Helpers ---

  defp gtd_request(event, payload) do
    envelope = Jason.encode!(Envelope.wrap(event, payload))
    nats_request(event, envelope)
  end

  defp nats_request(subject, body, timeout \\ @request_timeout) do
    payload = normalize_nats_payload(body)

    opts = [timeout_ms: timeout, circuit_breaker_key: "bridge_lite:#{subject}"]

    case Publisher.request(subject, payload, opts) do
      {:ok, response} when is_binary(response) ->
        {:ok, response}

      {:ok, response} when is_map(response) ->
        Jason.encode(response)

      {:ok, response} ->
        {:ok, to_string(response)}

      other ->
        other
    end
  end

  defp normalize_nats_payload(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} when is_map(map) -> map
      _ -> %{"raw" => body}
    end
  end

  defp normalize_nats_payload(map) when is_map(map) do
    map
  end

  defp reply(msg, body) do
    if msg.reply_to do
      Gnat.pub(Connection, msg.reply_to, body)
    end
  end

  defp decode_json(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, _} -> {:error, "expected JSON object"}
      {:error, _} = err -> err
    end
  end

  defp decode_json(nil), do: {:error, "empty body"}

  defp tenant_id,
    do: System.get_env("BOT_ARMY_TENANT_ID", "00000000-0000-0000-0000-000000000001")
end
