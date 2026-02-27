defmodule Liteskill.Chat.EventsTest do
  use ExUnit.Case, async: true

  alias Liteskill.Chat.Events
  alias Liteskill.Chat.Events.{ConversationCreated, UserMessageAdded, ConversationArchived}

  describe "serialize/1" do
    test "converts a ConversationCreated struct to event store format" do
      event = %ConversationCreated{
        conversation_id: "c1",
        user_id: "u1",
        title: "Test",
        model_id: "claude",
        system_prompt: nil
      }

      result = Events.serialize(event)
      assert result.event_type == "ConversationCreated"
      assert result.data["conversation_id"] == "c1"
      assert result.data["user_id"] == "u1"
      assert is_binary(Map.keys(result.data) |> Enum.at(0))
    end

    test "converts a ConversationArchived struct" do
      event = %ConversationArchived{timestamp: "2024-01-01T00:00:00Z"}
      result = Events.serialize(event)
      assert result.event_type == "ConversationArchived"
      assert result.data["timestamp"] == "2024-01-01T00:00:00Z"
    end
  end

  describe "deserialize/1" do
    test "converts event store format back to struct" do
      event = %{
        event_type: "UserMessageAdded",
        data: %{"message_id" => "m1", "content" => "hello", "timestamp" => "now"}
      }

      result = Events.deserialize(event)
      assert %UserMessageAdded{} = result
      assert result.message_id == "m1"
      assert result.content == "hello"
    end

    test "handles atom keys in data" do
      event = %{
        event_type: "ConversationArchived",
        data: %{timestamp: "now"}
      }

      result = Events.deserialize(event)
      assert %ConversationArchived{} = result
      assert result.timestamp == "now"
    end
  end

  describe "module_for/1" do
    test "returns the module for a known event type" do
      assert Events.module_for("ConversationCreated") == ConversationCreated
      assert Events.module_for("UserMessageAdded") == UserMessageAdded
    end

    test "raises for unknown event type" do
      assert_raise KeyError, fn ->
        Events.module_for("UnknownEvent")
      end
    end
  end
end
