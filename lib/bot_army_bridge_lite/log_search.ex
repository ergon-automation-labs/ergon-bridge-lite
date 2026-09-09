defmodule BotArmyBridgeLite.LogSearch do
  @moduledoc """
  Fleet log search for the `bridge.logs.search` request/reply subject.

  Serves the sre LogWatcher contract (bot_army_sre workers/log_watcher.ex):

    request:  %{"query" => "error|exception|...", "limit" => 50,
                "files" => ["/var/log/bot_army/<bot>.log", ...]}
    reply:    %{"ok" => true, "data" => %{"matches" =>
                 [%{"file" => ..., "line_number" => 1-based, "line" => ...}]}}

  The `files` paths are the per-bot container paths from the LogWatcher's
  static table; this responder resolves each against the FLEET LOG ROOT
  (env FLEET_LOG_ROOT, default /var/log/fleet — the stage compose mounts
  ./data/logs there read-only) by basename, guarded to stay inside the
  root. Missing files are skipped silently (bots come and go).

  Line numbers are 1-based per file — the LogWatcher keeps per-file cursors
  and detects rotation when numbers go backwards.
  """

  require Logger

  @default_root "/var/log/fleet"

  @doc """
  Search the given files for the query. Returns the reply-shaped map.

  The query is applied as an Erlang `re` pattern; if it is not a valid
  pattern it degrades to a case-insensitive substring match. Empty query
  matches nothing (defensive — a poll with no query is a bug).
  """
  @spec search(map()) :: map()
  def search(params) when is_map(params) do
    query = Map.get(params, "query", "")
    limit = Map.get(params, "limit", 50)
    files = Map.get(params, "files", [])

    cond do
      not is_binary(query) or query == "" ->
        error_reply("query required")

      not is_list(files) or files == [] ->
        error_reply("files list required")

      true ->
        matcher = build_matcher(query)
        matches = Enum.flat_map(files, &scan_file(&1, matcher)) |> Enum.take(limit)
        %{"ok" => true, "data" => %{"matches" => matches}}
    end
  end

  def search(_), do: error_reply("params must be an object")

  defp error_reply(msg), do: %{"ok" => false, "error" => msg}

  # ── File resolution (basename + containment under the fleet root) ──

  defp resolve_path(file) when is_binary(file) do
    root = resolved_root()
    base = Path.basename(String.trim(file))

    cond do
      base == "" or base in [".", ".."] ->
        :error

      true ->
        path = Path.join(root, base)
        if String.starts_with?(Path.expand(path), Path.expand(resolved_root()) <> "/"),
          do: {:ok, path},
          else: :error
    end
  end

  defp resolve_path(_), do: :error

  defp resolved_root do
    System.get_env("FLEET_LOG_ROOT", @default_root)
  end

  # ── Matching ──

  # Valid regex → :re pattern; anything else (invalid pattern, e.g. a raw
  # user string with stray characters) → substring match on the whole query.
  defp build_matcher(query) do
    case :re.compile(query) do
      {:ok, re} -> {:regex, re}
      {:error, _} -> {:substring, String.downcase(query)}
    end
  end

  defp line_matches?({:regex, re}, line) do
    :re.run(line, re, [{:capture, :none}]) == :match
  end

  defp line_matches?({:substring, needle}, line) do
    String.contains?(String.downcase(line), needle)
  end

  # ── Scanning ──

  defp scan_file(file, matcher) do
    with {:ok, path} <- resolve_path(file),
         {:ok, content} <- File.read(path) do
      content
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, n} ->
        if line_matches?(matcher, line) do
          [%{"file" => file, "line_number" => n, "line" => String.trim_trailing(line)}]
        else
          []
        end
      end)
    else
      _ -> []
    end
  end
end