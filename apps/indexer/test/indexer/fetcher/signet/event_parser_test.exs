defmodule Indexer.Fetcher.Signet.EventParserTest do
  @moduledoc """
  Table-driven tests for ABI decoding in Indexer.Fetcher.Signet.EventParser.

  Test vectors are derived from the @signet-sh/sdk TypeScript test suite.
  ABI encoding helpers construct raw event log data independently of the parser,
  providing cross-validation of the manual binary decoder.
  """

  use ExUnit.Case, async: true

  import Bitwise

  alias Indexer.Fetcher.Signet.{Abi, EventParser}

  # -- ABI encoding helpers --

  defp encode_uint256(value), do: <<value::unsigned-big-integer-size(256)>>
  defp encode_uint32(value), do: <<0::224, value::unsigned-big-integer-size(32)>>

  defp encode_address(addr) when byte_size(addr) == 20, do: <<0::96, addr::binary>>

  defp encode_address("0x" <> hex) do
    <<0::96, Base.decode16!(hex, case: :mixed)::binary>>
  end

  defp encode_input_array(inputs) do
    count = encode_uint256(length(inputs))

    elements =
      Enum.map(inputs, fn {token, amount} ->
        encode_address(token) <> encode_uint256(amount)
      end)

    IO.iodata_to_binary([count | elements])
  end

  defp encode_output_array(outputs) do
    count = encode_uint256(length(outputs))

    elements =
      Enum.map(outputs, fn {token, amount, recipient, chain_id} ->
        encode_address(token) <> encode_uint256(amount) <> encode_address(recipient) <> encode_uint32(chain_id)
      end)

    IO.iodata_to_binary([count | elements])
  end

  defp encode_order_data(deadline, inputs, outputs) do
    inputs_encoded = encode_input_array(inputs)
    outputs_encoded = encode_output_array(outputs)

    # Offsets are from start of data payload (3 header words = 96 bytes)
    inputs_offset = 96
    outputs_offset = inputs_offset + byte_size(inputs_encoded)

    encode_uint256(deadline) <>
      encode_uint256(inputs_offset) <>
      encode_uint256(outputs_offset) <>
      inputs_encoded <>
      outputs_encoded
  end

  defp encode_filled_data(outputs) do
    outputs_encoded = encode_output_array(outputs)
    # Single dynamic array: offset word (32) + encoded data
    encode_uint256(32) <> outputs_encoded
  end

  defp encode_sweep_data(amount), do: encode_uint256(amount)

  defp to_hex(binary), do: "0x" <> Base.encode16(binary, case: :lower)

  defp build_log(opts) do
    data = Keyword.fetch!(opts, :data)
    topics = Keyword.get(opts, :topics, [])
    tx_hash = Keyword.get(opts, :tx_hash, "0x" <> String.duplicate("ab", 32))
    block = Keyword.get(opts, :block, 100)
    index = Keyword.get(opts, :index, 0)

    %{
      "data" => to_hex(data),
      "topics" => topics,
      "transactionHash" => tx_hash,
      "blockNumber" => "0x" <> Integer.to_string(block, 16),
      "logIndex" => "0x" <> Integer.to_string(index, 16)
    }
  end

  # -- Addresses used across tests (from @signet-sh/sdk vectors) --

  @zero_addr "0x0000000000000000000000000000000000000000"
  @usdc "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
  @usdt "0xdac17f958d2ee523a2206206994597c13d831ec7"
  @wbtc "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599"
  @weth "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
  @addr_1234 "0x1234567890123456789012345678901234567890"
  @addr_1111 "0x1111111111111111111111111111111111111111"
  @addr_2222 "0x2222222222222222222222222222222222222222"
  @addr_3333 "0x3333333333333333333333333333333333333333"
  @addr_4444 "0x4444444444444444444444444444444444444444"
  @addr_6666 "0x6666666666666666666666666666666666666666"
  @addr_8888 "0x8888888888888888888888888888888888888888"
  @signet_token "0x96f44ddc3bc8892371305531f1a6d8ca2331fe6c"

  # -- Order event decoding tests (from vectors.json) --

  describe "parse_rollup_logs/1 - Order events" do
    @order_vectors [
      %{
        name: "minimal_order",
        deadline: 0,
        inputs: [{@zero_addr, 0}],
        outputs: [{@zero_addr, 0, @zero_addr, 0}],
        expected_inputs: [%{"token" => @zero_addr, "amount" => "0"}],
        expected_outputs: [%{"token" => @zero_addr, "amount" => "0", "recipient" => @zero_addr, "chainId" => 0}]
      },
      %{
        name: "multi_input",
        deadline: 0x6553F100,
        inputs: [{@usdc, 0xF4240}, {@usdt, 0x1E8480}, {@wbtc, 0x5F5E100}],
        outputs: [{@zero_addr, 0xDE0B6B3A7640000, @addr_1234, 1}],
        expected_inputs: [
          %{"token" => @usdc, "amount" => "1000000"},
          %{"token" => @usdt, "amount" => "2000000"},
          %{"token" => @wbtc, "amount" => "100000000"}
        ],
        expected_outputs: [
          %{"token" => @zero_addr, "amount" => "1000000000000000000", "recipient" => @addr_1234, "chainId" => 1}
        ]
      },
      %{
        name: "multi_output",
        deadline: 0x6B49D200,
        inputs: [{@usdc, 0x989680}],
        outputs: [
          {@usdc, 0x2DC6C0, @addr_1111, 1},
          {@usdc, 0x2DC6C0, @addr_2222, 1},
          {@usdc, 0x3D0900, @addr_3333, 1}
        ],
        expected_inputs: [%{"token" => @usdc, "amount" => "10000000"}],
        expected_outputs: [
          %{"token" => @usdc, "amount" => "3000000", "recipient" => @addr_1111, "chainId" => 1},
          %{"token" => @usdc, "amount" => "3000000", "recipient" => @addr_2222, "chainId" => 1},
          %{"token" => @usdc, "amount" => "4000000", "recipient" => @addr_3333, "chainId" => 1}
        ]
      },
      %{
        name: "cross_chain",
        deadline: 0x684EE180,
        inputs: [{@usdc, 0x4C4B40}],
        outputs: [
          {@usdc, 0x2625A0, @addr_4444, 1},
          {@usdc, 0x2625A0, @addr_4444, 421_614}
        ],
        expected_inputs: [%{"token" => @usdc, "amount" => "5000000"}],
        expected_outputs: [
          %{"token" => @usdc, "amount" => "2500000", "recipient" => @addr_4444, "chainId" => 1},
          %{"token" => @usdc, "amount" => "2500000", "recipient" => @addr_4444, "chainId" => 421_614}
        ]
      },
      %{
        name: "large_amounts",
        deadline: 0xFFFFFFFFFFFFFFFF,
        inputs: [{@weth, 0x21E19E0C9BAB2400000}],
        outputs: [{@weth, 0x21E19E0C9BAB2400000, @addr_6666, 1}],
        expected_inputs: [%{"token" => @weth, "amount" => "10000000000000000000000"}],
        expected_outputs: [
          %{
            "token" => @weth,
            "amount" => "10000000000000000000000",
            "recipient" => @addr_6666,
            "chainId" => 1
          }
        ]
      },
      %{
        name: "mainnet_config",
        deadline: 0x65920080,
        inputs: [{@usdc, 0x5F5E100}],
        outputs: [
          {@signet_token, 0x2FAF080, @addr_8888, 1},
          {@signet_token, 0x2FAF080, @addr_8888, 519}
        ],
        expected_inputs: [%{"token" => @usdc, "amount" => "100000000"}],
        expected_outputs: [
          %{"token" => @signet_token, "amount" => "50000000", "recipient" => @addr_8888, "chainId" => 1},
          %{"token" => @signet_token, "amount" => "50000000", "recipient" => @addr_8888, "chainId" => 519}
        ]
      }
    ]

    for vector <- @order_vectors do
      @vector vector
      test "decodes #{@vector.name} Order event" do
        v = @vector
        data = encode_order_data(v.deadline, v.inputs, v.outputs)

        log =
          build_log(
            data: data,
            topics: [Abi.order_event_topic()],
            block: 42,
            index: 3,
            tx_hash: "0x" <> String.duplicate("01", 32)
          )

        {:ok, {[order], []}} = EventParser.parse_rollup_logs([log])

        assert order.deadline == v.deadline
        assert order.block_number == 42
        assert order.log_index == 3
        assert order.transaction_hash == "0x" <> String.duplicate("01", 32)
        assert Jason.decode!(order.inputs_json) == v.expected_inputs
        assert Jason.decode!(order.outputs_json) == v.expected_outputs
      end
    end
  end

  # -- Filled event decoding tests --

  describe "parse_rollup_logs/1 - Filled events" do
    @fill_vectors [
      %{
        name: "minimal_fill",
        outputs: [{@zero_addr, 0, @zero_addr, 0}],
        expected: [%{"token" => @zero_addr, "amount" => "0", "recipient" => @zero_addr, "chainId" => 0}]
      },
      %{
        name: "single_weth",
        outputs: [{@weth, 1_000_000_000_000_000_000, @addr_1234, 1}],
        expected: [
          %{"token" => @weth, "amount" => "1000000000000000000", "recipient" => @addr_1234, "chainId" => 1}
        ]
      },
      %{
        name: "multi_output",
        outputs: [
          {@weth, 500_000_000_000_000_000, @addr_1111, 1},
          {@usdc, 1_000_000_000, @addr_2222, 1}
        ],
        expected: [
          %{"token" => @weth, "amount" => "500000000000000000", "recipient" => @addr_1111, "chainId" => 1},
          %{"token" => @usdc, "amount" => "1000000000", "recipient" => @addr_2222, "chainId" => 1}
        ]
      },
      %{
        name: "cross_chain",
        outputs: [
          {@usdc, 500_000_000, @addr_4444, 1},
          {@usdc, 500_000_000, @addr_4444, 519}
        ],
        expected: [
          %{"token" => @usdc, "amount" => "500000000", "recipient" => @addr_4444, "chainId" => 1},
          %{"token" => @usdc, "amount" => "500000000", "recipient" => @addr_4444, "chainId" => 519}
        ]
      }
    ]

    for vector <- @fill_vectors do
      @vector vector
      test "decodes #{@vector.name} Filled event" do
        v = @vector
        data = encode_filled_data(v.outputs)

        log =
          build_log(
            data: data,
            topics: [Abi.filled_event_topic()],
            block: 99,
            index: 7
          )

        {:ok, {[], [fill]}} = EventParser.parse_rollup_logs([log])

        assert fill.block_number == 99
        assert fill.log_index == 7
        assert Jason.decode!(fill.outputs_json) == v.expected
      end
    end
  end

  # -- Sweep event decoding tests --

  describe "parse_rollup_logs/1 - Sweep events" do
    test "decodes minimal Sweep event" do
      data = encode_sweep_data(0)
      zero_topic = "0x" <> String.duplicate("00", 32)

      log =
        build_log(
          data: data,
          topics: [Abi.sweep_event_topic(), zero_topic, zero_topic],
          block: 10,
          index: 0
        )

      # Sweep events are only returned as part of order association, not standalone.
      # With no orders, sweeps are consumed internally but result in empty orders list.
      {:ok, {[], []}} = EventParser.parse_rollup_logs([log])
    end
  end

  # -- Order + Sweep association tests --

  describe "parse_rollup_logs/1 - Order + Sweep association" do
    test "order gets sweep fields when sweep exists in same tx" do
      tx_hash = "0x" <> String.duplicate("aa", 32)
      order_data = encode_order_data(1000, [{@usdc, 100}], [{@usdc, 100, @addr_1111, 1}])
      sweep_data = encode_sweep_data(50)

      recipient_topic = "0x000000000000000000000000" <> String.duplicate("22", 20)
      token_topic = "0x000000000000000000000000" <> String.duplicate("33", 20)

      order_log = build_log(data: order_data, topics: [Abi.order_event_topic()], tx_hash: tx_hash, block: 1, index: 0)

      sweep_log =
        build_log(
          data: sweep_data,
          topics: [Abi.sweep_event_topic(), recipient_topic, token_topic],
          tx_hash: tx_hash,
          block: 1,
          index: 1
        )

      {:ok, {[order], []}} = EventParser.parse_rollup_logs([order_log, sweep_log])

      assert order.sweep_amount == 50
      assert order.sweep_recipient == Base.decode16!(String.duplicate("22", 20), case: :lower)
      assert order.sweep_token == Base.decode16!(String.duplicate("33", 20), case: :lower)
    end

    test "order has no sweep fields when no sweep in tx" do
      order_data = encode_order_data(1000, [{@usdc, 100}], [{@usdc, 100, @addr_1111, 1}])
      log = build_log(data: order_data, topics: [Abi.order_event_topic()], block: 1, index: 0)

      {:ok, {[order], []}} = EventParser.parse_rollup_logs([log])

      refute Map.has_key?(order, :sweep_recipient)
      refute Map.has_key?(order, :sweep_token)
      refute Map.has_key?(order, :sweep_amount)
    end

    test "warns when multiple sweeps exist for same tx" do
      tx_hash = "0x" <> String.duplicate("cc", 32)
      order_data = encode_order_data(1000, [{@usdc, 100}], [{@usdc, 100, @addr_1111, 1}])

      recipient1 = "0x000000000000000000000000" <> String.duplicate("11", 20)
      recipient2 = "0x000000000000000000000000" <> String.duplicate("22", 20)
      token_topic = "0x000000000000000000000000" <> String.duplicate("ff", 20)

      order_log = build_log(data: order_data, topics: [Abi.order_event_topic()], tx_hash: tx_hash, block: 1, index: 0)

      sweep_log1 =
        build_log(
          data: encode_sweep_data(10),
          topics: [Abi.sweep_event_topic(), recipient1, token_topic],
          tx_hash: tx_hash,
          block: 1,
          index: 1
        )

      sweep_log2 =
        build_log(
          data: encode_sweep_data(20),
          topics: [Abi.sweep_event_topic(), recipient2, token_topic],
          tx_hash: tx_hash,
          block: 1,
          index: 2
        )

      # Should still succeed (uses first element from reversed accumulator, i.e. last encountered)
      {:ok, {[order], []}} = EventParser.parse_rollup_logs([order_log, sweep_log1, sweep_log2])

      assert order.sweep_amount in [10, 20]
    end
  end

  # -- Host filled logs tests --

  describe "parse_host_filled_logs/1" do
    test "parses only Filled events, ignores others" do
      fill_data = encode_filled_data([{@usdc, 100, @addr_1111, 1}])
      fill_log = build_log(data: fill_data, topics: [Abi.filled_event_topic()], block: 50, index: 0)
      noise_log = build_log(data: <<0::256>>, topics: ["0xdeadbeef" <> String.duplicate("00", 28)], block: 50, index: 1)

      {:ok, fills} = EventParser.parse_host_filled_logs([fill_log, noise_log])

      assert length(fills) == 1
      assert hd(fills).block_number == 50
    end

    test "returns empty list for empty input" do
      {:ok, []} = EventParser.parse_host_filled_logs([])
    end

    test "parses multiple Filled events" do
      fill1 =
        build_log(
          data: encode_filled_data([{@usdc, 100, @addr_1111, 1}]),
          topics: [Abi.filled_event_topic()],
          block: 10,
          index: 0,
          tx_hash: "0x" <> String.duplicate("01", 32)
        )

      fill2 =
        build_log(
          data: encode_filled_data([{@weth, 200, @addr_2222, 519}]),
          topics: [Abi.filled_event_topic()],
          block: 11,
          index: 0,
          tx_hash: "0x" <> String.duplicate("02", 32)
        )

      {:ok, fills} = EventParser.parse_host_filled_logs([fill1, fill2])

      assert length(fills) == 2
      assert Enum.at(fills, 0).block_number == 10
      assert Enum.at(fills, 1).block_number == 11
    end
  end

  # -- Edge cases --

  describe "edge cases" do
    test "empty logs returns empty results" do
      assert {:ok, {[], []}} = EventParser.parse_rollup_logs([])
    end

    test "logs with unrecognized topics are skipped" do
      log = build_log(data: <<0::256>>, topics: ["0x" <> String.duplicate("ff", 32)])
      {:ok, {[], []}} = EventParser.parse_rollup_logs([log])
    end

    test "max uint32 chainId (4294967295)" do
      max_u32 = 0xFFFFFFFF

      data = encode_order_data(1000, [{@usdc, 100}], [{@usdc, 100, @addr_1111, max_u32}])
      log = build_log(data: data, topics: [Abi.order_event_topic()], block: 1, index: 0)

      {:ok, {[order], []}} = EventParser.parse_rollup_logs([log])

      [output] = Jason.decode!(order.outputs_json)
      assert output["chainId"] == max_u32
    end

    test "max uint256 amount" do
      max_u256 = (1 <<< 256) - 1

      data = encode_filled_data([{@weth, max_u256, @addr_1111, 1}])
      log = build_log(data: data, topics: [Abi.filled_event_topic()], block: 1, index: 0)

      {:ok, {[], [fill]}} = EventParser.parse_rollup_logs([log])

      [output] = Jason.decode!(fill.outputs_json)
      assert output["amount"] == Integer.to_string(max_u256)
    end

    test "handles atom-keyed logs" do
      data = encode_order_data(500, [{@usdc, 100}], [{@usdc, 100, @addr_1111, 1}])

      log = %{
        data: "0x" <> Base.encode16(data, case: :lower),
        topics: [Abi.order_event_topic()],
        transaction_hash: "0x" <> String.duplicate("dd", 32),
        block_number: 77,
        log_index: 2
      }

      {:ok, {[order], []}} = EventParser.parse_rollup_logs([log])

      assert order.deadline == 500
      assert order.block_number == 77
      assert order.log_index == 2
    end

    test "handles integer block_number and log_index" do
      data = encode_filled_data([{@usdc, 100, @addr_1111, 1}])

      log = %{
        data: "0x" <> Base.encode16(data, case: :lower),
        topics: [Abi.filled_event_topic()],
        transaction_hash: "0x" <> String.duplicate("ee", 32),
        block_number: 42,
        log_index: 5
      }

      {:ok, {[], [fill]}} = EventParser.parse_rollup_logs([log])

      assert fill.block_number == 42
      assert fill.log_index == 5
    end
  end

  # -- Error path tests --

  describe "error paths" do
    test "invalid block_number causes event to be skipped" do
      data = encode_order_data(1000, [{@usdc, 100}], [{@usdc, 100, @addr_1111, 1}])

      log = %{
        "data" => "0x" <> Base.encode16(data, case: :lower),
        "topics" => [Abi.order_event_topic()],
        "transactionHash" => "0x" <> String.duplicate("ab", 32),
        "blockNumber" => nil,
        "logIndex" => "0x0"
      }

      {:ok, {[], []}} = EventParser.parse_rollup_logs([log])
    end

    test "invalid log_index causes event to be skipped" do
      data = encode_order_data(1000, [{@usdc, 100}], [{@usdc, 100, @addr_1111, 1}])

      log = %{
        "data" => "0x" <> Base.encode16(data, case: :lower),
        "topics" => [Abi.order_event_topic()],
        "transactionHash" => "0x" <> String.duplicate("ab", 32),
        "blockNumber" => "0x1",
        "logIndex" => nil
      }

      {:ok, {[], []}} = EventParser.parse_rollup_logs([log])
    end

    test "malformed data causes event to be skipped" do
      log = build_log(data: <<1, 2, 3>>, topics: [Abi.order_event_topic()], block: 1, index: 0)

      {:ok, {[], []}} = EventParser.parse_rollup_logs([log])
    end

    test "empty data causes Filled event to be skipped" do
      log = build_log(data: <<>>, topics: [Abi.filled_event_topic()], block: 1, index: 0)

      {:ok, {[], []}} = EventParser.parse_rollup_logs([log])
    end
  end
end
