defmodule BotArmyBridgeLite.EnvelopeTest do
  use ExUnit.Case, async: true
  @moduletag :core

  alias BotArmyBridgeLite.Envelope

  describe "wrap/2" do
    test "builds envelope with all required fields" do
      payload = %{"title" => "Test task"}
      result = Envelope.wrap("gtd.task.create", payload)

      assert result["event"] == "gtd.task.create"
      assert result["source"] == "bridge_lite"
      assert result["triggered_by"] == "user"
      assert result["schema_version"] == "1.0"
      assert result["payload"] == payload
    end

    test "generates unique event_id" do
      result1 = Envelope.wrap("gtd.task.create", %{"title" => "a"})
      result2 = Envelope.wrap("gtd.task.create", %{"title" => "b"})

      assert result1["event_id"] != result2["event_id"]
    end

    test "includes ISO8601 timestamp" do
      result = Envelope.wrap("gtd.task.create", %{})

      assert String.contains?(result["timestamp"], "T")

      assert String.ends_with?(result["timestamp"], "Z") or
               String.match?(result["timestamp"], ~r/[+-]\d{2}:\d{2}$/)
    end

    test "uses default tenant_id when env var not set" do
      result = Envelope.wrap("gtd.task.create", %{})

      assert result["tenant_id"] == "00000000-0000-0000-0000-000000000001"
    end

    test "uses default user_id when env var not set" do
      result = Envelope.wrap("gtd.task.create", %{})

      assert result["user_id"] == "00000000-0000-0000-0000-000000000002"
    end

    test "preserves payload exactly" do
      payload = %{"task_id" => "abc-123", "title" => "My Task", "priority" => "high"}
      result = Envelope.wrap("gtd.task.update", payload)

      assert result["payload"] == payload
    end

    test "includes source_node as string" do
      result = Envelope.wrap("gtd.task.create", %{})

      assert is_binary(result["source_node"])
    end
  end
end
