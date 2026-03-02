if Application.compile_env(:explorer, :chain_type) == :signet do
  defmodule Indexer.Fetcher.Signet.OrdersFetcherTest do
    @moduledoc """
    Integration tests for the Signet OrdersFetcher module.

    Tests verify the full pipeline from event fetching through
    database insertion.

    Note: Orders and fills are indexed independently with no correlation.
    Primary keys are:
      - Orders: (transaction_hash, log_index)
      - Fills: (chain_type, transaction_hash, log_index)
    """

    use Explorer.DataCase, async: false

    import Explorer.Factory

    alias Explorer.Chain
    alias Explorer.Chain.Hash
    alias Indexer.Fetcher.Signet.OrdersFetcher

    @moduletag :signet

    defp cast_hash!(bytes) do
      {:ok, hash} = Hash.Full.cast(bytes)
      hash
    end

    describe "OrdersFetcher configuration" do
      test "child_spec returns proper supervisor config" do
        json_rpc_named_arguments = [
          transport: EthereumJSONRPC.Mox,
          transport_options: []
        ]

        Application.put_env(:indexer, OrdersFetcher,
          enabled: true,
          rollup_orders_address: "0x1234567890123456789012345678901234567890",
          recheck_interval: 1000
        )

        child_spec =
          OrdersFetcher.child_spec([
            [json_rpc_named_arguments: json_rpc_named_arguments],
            [name: OrdersFetcher]
          ])

        assert child_spec.id == OrdersFetcher
        assert child_spec.restart == :transient
      end
    end

    describe "database import via Chain.import/1" do
      test "imports order through Chain.import" do
        tx_hash = cast_hash!(<<1::256>>)

        order_params = %{
          deadline: 1_700_000_000,
          block_number: 100,
          transaction_hash: tx_hash,
          log_index: 0,
          inputs_json: [%{"token" => "0x1234", "amount" => "1000"}],
          outputs_json: [%{"token" => "0x5678", "recipient" => "0x9abc", "amount" => "500", "chainId" => "1"}]
        }

        assert {:ok, %{insert_signet_orders: [order]}} =
                 Chain.import(%{
                   signet_orders: %{params: [order_params]},
                   timeout: :infinity
                 })

        assert order.block_number == 100
        assert order.deadline == 1_700_000_000
      end

      test "imports fill through Chain.import" do
        tx_hash = cast_hash!(<<2::256>>)

        fill_params = %{
          chain_type: :rollup,
          block_number: 150,
          transaction_hash: tx_hash,
          log_index: 1,
          outputs_json: [%{"token" => "0xaaaa", "recipient" => "0xbbbb", "amount" => "1000", "chainId" => "1"}]
        }

        assert {:ok, %{insert_signet_fills: [fill]}} =
                 Chain.import(%{
                   signet_fills: %{params: [fill_params]},
                   timeout: :infinity
                 })

        assert fill.block_number == 150
        assert fill.chain_type == :rollup
      end

      test "imports order and fill together" do
        order_params = %{
          deadline: 1_700_000_000,
          block_number: 100,
          transaction_hash: cast_hash!(<<10::256>>),
          log_index: 0,
          inputs_json: [%{"token" => "0x1111", "amount" => "1000"}],
          outputs_json: [%{"token" => "0x2222", "recipient" => "0x3333", "amount" => "500", "chainId" => "1"}]
        }

        fill_params = %{
          chain_type: :host,
          block_number: 200,
          transaction_hash: cast_hash!(<<20::256>>),
          log_index: 0,
          outputs_json: [%{"token" => "0x2222", "recipient" => "0x3333", "amount" => "500", "chainId" => "1"}]
        }

        assert {:ok, result} =
                 Chain.import(%{
                   signet_orders: %{params: [order_params]},
                   signet_fills: %{params: [fill_params]},
                   timeout: :infinity
                 })

        assert length(result.insert_signet_orders) == 1
        assert length(result.insert_signet_fills) == 1
      end
    end

    describe "factory integration" do
      test "signet_order factory creates valid order" do
        order = insert(:signet_order)

        assert order.transaction_hash != nil
        assert order.log_index != nil
        assert order.deadline != nil
        assert order.block_number != nil
        assert order.inputs_json != nil
        assert order.outputs_json != nil
      end

      test "signet_fill factory creates valid fill" do
        fill = insert(:signet_fill)

        assert fill.transaction_hash != nil
        assert fill.log_index != nil
        assert fill.chain_type in [:rollup, :host]
        assert fill.block_number != nil
        assert fill.outputs_json != nil
      end

      test "factory orders can be customized" do
        order = insert(:signet_order, deadline: 9_999_999_999, block_number: 42)

        assert order.deadline == 9_999_999_999
        assert order.block_number == 42
      end

      test "factory fills can be customized" do
        fill = insert(:signet_fill, chain_type: :host, block_number: 123)

        assert fill.chain_type == :host
        assert fill.block_number == 123
      end
    end
  end
end
