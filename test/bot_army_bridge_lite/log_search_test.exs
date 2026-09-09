defmodule BotArmyBridgeLite.LogSearchTest do
  use ExUnit.Case, async: false

  alias BotArmyBridgeLite.LogSearch

  @root_tmp System.tmp_dir!()

  setup do
    # Fresh fleet-logs root per test
    root = Path.join(@root_tmp, "bridge_lite_logtest_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    System.put_env("FLEET_LOG_ROOT", root)

    on_exit(fn ->
      System.delete_env("FLEET_LOG_ROOT")
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  defp write_log(root, name, lines) do
    path = Path.join(root, name)
    File.write!(path, Enum.join(lines, "\n") <> "\n")
    path
  end

  describe "search/1 contract" do
    test "returns 1-based line numbers for regex query matches", %{root: root} do
      write_log(root, "sre_bot.log", [
        "13:00:01 nominal startup",
        "13:00:02 [error] boom",
        "13:00:03 all good",
        "13:00:04 [error] second boom"
      ])

      reply =
        LogSearch.search(%{
          "query" => "error|exception|no_responders|timeout",
          "limit" => 50,
          "files" => ["/var/log/bot_army/sre_bot.log"]
        })

      assert reply["ok"] == true
      matches = reply["data"]["matches"]
      assert [%{"line_number" => 2}, %{"line_number" => 4}] = matches
      assert hd(matches)["line"] == "13:00:02 [error] boom"
      assert hd(matches)["file"] == "/var/log/bot_army/sre_bot.log"
    end

    test "scans multiple files, skipping missing ones", %{root: root} do
      write_log(root, "a.log", ["x error x", "clean"])
      write_log(root, "b.log", ["timeout while waiting", "ok"])

      reply =
        LogSearch.search(%{
          "query" => "error|timeout",
          "limit" => 50,
          "files" => ["/var/log/bot_army/a.log", "/var/log/bot_army/missing.log", "/var/log/bot_army/b.log"]
        })

      matches = reply["data"]["matches"]
      assert length(matches) == 2
      assert [%{"line_number" => 1, "line" => "x error x"}, %{"line_number" => 1, "line" => "timeout while waiting"}] = matches
    end

    test "limit caps matches", %{root: root} do
      write_log(root, "chatty.log", for(i <- 1..10, do: "error line #{i}"))

      reply =
        LogSearch.search(%{"query" => "error", "limit" => 3, "files" => ["/var/log/bot_army/chatty.log"]})

      assert length(reply["data"]["matches"]) == 3
    end

    test "invalid regex query degrades to substring match", %{root: root} do
      write_log(root, "plain.log", ["error: unmatched ( paren", "fine"])

      reply =
        LogSearch.search(%{
          "query" => "unmatched ( paren",
          "limit" => 10,
          "files" => ["/var/log/bot_army/plain.log"]
        })

      assert [%{"line_number" => 1}] = reply["data"]["matches"]
    end

    test "path traversal is contained — only basenames under the root resolve", %{root: root} do
      write_log(root, "real.log", ["error here"])
      secret = Path.join(@root_tmp, "outside_#{System.unique_integer()}.log")
      File.write!(secret, "error secret")
      on_exit(fn -> File.rm!(secret) end)

      reply =
        LogSearch.search(%{
          "query" => "error",
          "limit" => 10,
          "files" => [
            "/var/log/bot_army/../../outside_#{Path.basename(secret)}",
            "/var/log/bot_army/real.log"
          ]
        })

      # The traversal path does not escape the root; the real file is scanned.
      paths = Enum.map(reply["data"]["matches"], & &1["file"])
      assert paths == ["/var/log/bot_army/real.log"]
    end

    test "nested fleet layout: per-bot dir under the root resolves too", %{root: root} do
      File.mkdir_p!(Path.join(root, "sre_bot"))
      File.write!(Path.join([root, "sre_bot", "sre_bot.log"]), "nested error here\n")

      reply =
        LogSearch.search(%{
          "query" => "error",
          "limit" => 10,
          "files" => ["/var/log/bot_army/sre_bot.log"]
        })

      assert [%{"line_number" => 1, "line" => "nested error here"}] = reply["data"]["matches"]
    end

    test "errors: empty query, empty files, non-map params" do
      assert %{"ok" => false} = LogSearch.search(%{"query" => "", "files" => ["/x.log"]})
      assert %{"ok" => false} = LogSearch.search(%{"query" => "error", "files" => []})
      assert %{"ok" => false} = LogSearch.search("not a map")
    end
  end
end