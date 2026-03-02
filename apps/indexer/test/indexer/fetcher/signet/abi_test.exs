defmodule Indexer.Fetcher.Signet.AbiTest do
  @moduledoc """
  Unit tests for Indexer.Fetcher.Signet.Abi module.
  """

  use ExUnit.Case, async: true

  alias Indexer.Fetcher.Signet.Abi

  # Expected topic hashes computed from keccak256 of canonical event signatures
  # Order(uint256,(address,uint256)[],(address,uint256,address,uint32)[])
  @expected_order_topic "0x" <>
                          Base.encode16(
                            ExKeccak.hash_256(
                              "Order(uint256,(address,uint256)[],(address,uint256,address,uint32)[])"
                            ),
                            case: :lower
                          )

  # Filled((address,uint256,address,uint32)[])
  @expected_filled_topic "0x" <>
                           Base.encode16(
                             ExKeccak.hash_256("Filled((address,uint256,address,uint32)[])"),
                             case: :lower
                           )

  # Sweep(address,address,uint256)
  @expected_sweep_topic "0x" <>
                          Base.encode16(ExKeccak.hash_256("Sweep(address,address,uint256)"), case: :lower)

  describe "event topic hashes" do
    test "event topics are different from each other" do
      order_topic = Abi.order_event_topic()
      filled_topic = Abi.filled_event_topic()
      sweep_topic = Abi.sweep_event_topic()

      refute order_topic == filled_topic
      refute order_topic == sweep_topic
      refute filled_topic == sweep_topic
    end

    test "order event topic matches expected keccak256 hash" do
      assert Abi.order_event_topic() == @expected_order_topic
    end

    test "filled event topic matches expected keccak256 hash" do
      assert Abi.filled_event_topic() == @expected_filled_topic
    end

    test "sweep event topic matches expected keccak256 hash" do
      assert Abi.sweep_event_topic() == @expected_sweep_topic
    end

    test "topic hashes are valid 66-char hex strings" do
      for topic <- [Abi.order_event_topic(), Abi.filled_event_topic(), Abi.sweep_event_topic()] do
        assert String.length(topic) == 66
        assert String.starts_with?(topic, "0x")
        assert Regex.match?(~r/^0x[0-9a-f]{64}$/, topic)
      end
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
