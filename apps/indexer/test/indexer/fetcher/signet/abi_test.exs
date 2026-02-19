defmodule Indexer.Fetcher.Signet.AbiTest do
  @moduledoc """
  Unit tests for Indexer.Fetcher.Signet.Abi module.
  """

  use ExUnit.Case, async: true

  alias Indexer.Fetcher.Signet.Abi

  describe "event topic hashes" do
    test "event topics are different from each other" do
      order_topic = Abi.order_event_topic()
      filled_topic = Abi.filled_event_topic()
      sweep_topic = Abi.sweep_event_topic()

      refute order_topic == filled_topic
      refute order_topic == sweep_topic
      refute filled_topic == sweep_topic
    end
  end

  describe "rollup_orders_event_topics/0" do
    test "returns list of three topics" do
      topics = Abi.rollup_orders_event_topics()

      assert length(topics) == 3
      assert Abi.order_event_topic() in topics
      assert Abi.filled_event_topic() in topics
      assert Abi.sweep_event_topic() in topics
    end
  end

  describe "host_orders_event_topics/0" do
    test "returns list with only filled topic" do
      topics = Abi.host_orders_event_topics()

      assert topics == [Abi.filled_event_topic()]
    end
  end
end
