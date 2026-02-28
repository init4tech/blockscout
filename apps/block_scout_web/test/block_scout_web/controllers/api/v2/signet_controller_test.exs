if Application.compile_env(:explorer, :chain_type) == :signet do
  defmodule BlockScoutWeb.API.V2.SignetControllerTest do
    use BlockScoutWeb.ConnCase

    @moduletag :signet

    describe "GET /api/v2/signet/orders" do
      test "returns paginated orders", %{conn: conn} do
        order1 = insert(:signet_order, log_index: 0, block_number: 100)
        order2 = insert(:signet_order, log_index: 1, block_number: 101)
        order3 = insert(:signet_order, log_index: 2, block_number: 102)

        conn = get(conn, "/api/v2/signet/orders")

        assert %{"items" => items} = json_response(conn, 200)
        assert length(items) == 3

        # Orders should be returned in descending block_number order
        block_numbers = Enum.map(items, & &1["block_number"])
        assert block_numbers == [order3.block_number, order2.block_number, order1.block_number]
      end

      test "filters by block_number_gte", %{conn: conn} do
        _order1 = insert(:signet_order, log_index: 0, block_number: 100)
        order2 = insert(:signet_order, log_index: 1, block_number: 200)
        order3 = insert(:signet_order, log_index: 2, block_number: 300)

        conn = get(conn, "/api/v2/signet/orders", %{"block_number_gte" => "150"})

        assert %{"items" => items} = json_response(conn, 200)
        assert length(items) == 2

        block_numbers = Enum.map(items, & &1["block_number"])
        assert order2.block_number in block_numbers
        assert order3.block_number in block_numbers
      end

      test "filters by block_number_lte", %{conn: conn} do
        order1 = insert(:signet_order, log_index: 0, block_number: 100)
        order2 = insert(:signet_order, log_index: 1, block_number: 200)
        _order3 = insert(:signet_order, log_index: 2, block_number: 300)

        conn = get(conn, "/api/v2/signet/orders", %{"block_number_lte" => "250"})

        assert %{"items" => items} = json_response(conn, 200)
        assert length(items) == 2

        block_numbers = Enum.map(items, & &1["block_number"])
        assert order1.block_number in block_numbers
        assert order2.block_number in block_numbers
      end

      test "returns empty list when no orders exist", %{conn: conn} do
        conn = get(conn, "/api/v2/signet/orders")

        assert %{"items" => items} = json_response(conn, 200)
        assert items == []
      end
    end

    describe "GET /api/v2/signet/orders/count" do
      test "returns total count of orders", %{conn: conn} do
        insert(:signet_order, log_index: 0)
        insert(:signet_order, log_index: 1)
        insert(:signet_order, log_index: 2)

        conn = get(conn, "/api/v2/signet/orders/count")

        assert json_response(conn, 200) == 3
      end

      test "returns 0 when no orders exist", %{conn: conn} do
        conn = get(conn, "/api/v2/signet/orders/count")

        assert json_response(conn, 200) == 0
      end
    end

    describe "GET /api/v2/signet/orders/:transaction_hash/:log_index" do
      test "returns single order by transaction hash and log index", %{conn: conn} do
        order = insert(:signet_order, log_index: 5, block_number: 100)

        conn =
          get(conn, "/api/v2/signet/orders/#{order.transaction_hash}/#{order.log_index}")

        result = json_response(conn, 200)
        assert result["transaction_hash"] == to_string(order.transaction_hash)
        assert result["log_index"] == order.log_index
        assert result["block_number"] == order.block_number
        assert result["deadline"] == order.deadline
      end

      test "returns 404 for non-existent order", %{conn: conn} do
        fake_hash = "0x" <> String.duplicate("00", 32)

        conn = get(conn, "/api/v2/signet/orders/#{fake_hash}/0")

        assert json_response(conn, 404)
      end

      test "returns 404 for invalid transaction hash", %{conn: conn} do
        conn = get(conn, "/api/v2/signet/orders/invalid_hash/0")

        assert json_response(conn, 404)
      end
    end

    describe "GET /api/v2/signet/fills" do
      test "returns paginated fills", %{conn: conn} do
        fill1 = insert(:signet_fill, chain_type: :rollup, log_index: 0, block_number: 100)
        fill2 = insert(:signet_fill, chain_type: :host, log_index: 1, block_number: 101)
        fill3 = insert(:signet_fill, chain_type: :rollup, log_index: 2, block_number: 102)

        conn = get(conn, "/api/v2/signet/fills")

        assert %{"items" => items} = json_response(conn, 200)
        assert length(items) == 3

        # Fills should be returned in descending block_number order
        block_numbers = Enum.map(items, & &1["block_number"])
        assert block_numbers == [fill3.block_number, fill2.block_number, fill1.block_number]
      end

      test "filters by chain_type=rollup", %{conn: conn} do
        _fill1 = insert(:signet_fill, chain_type: :host, log_index: 0, block_number: 100)
        fill2 = insert(:signet_fill, chain_type: :rollup, log_index: 1, block_number: 101)
        fill3 = insert(:signet_fill, chain_type: :rollup, log_index: 2, block_number: 102)

        conn = get(conn, "/api/v2/signet/fills", %{"chain_type" => "rollup"})

        assert %{"items" => items} = json_response(conn, 200)
        assert length(items) == 2

        assert Enum.all?(items, &(&1["chain_type"] == "rollup"))
        block_numbers = Enum.map(items, & &1["block_number"])
        assert fill2.block_number in block_numbers
        assert fill3.block_number in block_numbers
      end

      test "filters by chain_type=host", %{conn: conn} do
        fill1 = insert(:signet_fill, chain_type: :host, log_index: 0, block_number: 100)
        _fill2 = insert(:signet_fill, chain_type: :rollup, log_index: 1, block_number: 101)
        _fill3 = insert(:signet_fill, chain_type: :rollup, log_index: 2, block_number: 102)

        conn = get(conn, "/api/v2/signet/fills", %{"chain_type" => "host"})

        assert %{"items" => items} = json_response(conn, 200)
        assert length(items) == 1
        assert hd(items)["chain_type"] == "host"
        assert hd(items)["block_number"] == fill1.block_number
      end

      test "filters by block_number_gte", %{conn: conn} do
        _fill1 = insert(:signet_fill, chain_type: :rollup, log_index: 0, block_number: 100)
        fill2 = insert(:signet_fill, chain_type: :rollup, log_index: 1, block_number: 200)
        fill3 = insert(:signet_fill, chain_type: :rollup, log_index: 2, block_number: 300)

        conn = get(conn, "/api/v2/signet/fills", %{"block_number_gte" => "150"})

        assert %{"items" => items} = json_response(conn, 200)
        assert length(items) == 2

        block_numbers = Enum.map(items, & &1["block_number"])
        assert fill2.block_number in block_numbers
        assert fill3.block_number in block_numbers
      end

      test "returns empty list when no fills exist", %{conn: conn} do
        conn = get(conn, "/api/v2/signet/fills")

        assert %{"items" => items} = json_response(conn, 200)
        assert items == []
      end
    end

    describe "GET /api/v2/signet/fills/count" do
      test "returns total count of fills", %{conn: conn} do
        insert(:signet_fill, chain_type: :rollup, log_index: 0)
        insert(:signet_fill, chain_type: :host, log_index: 1)
        insert(:signet_fill, chain_type: :rollup, log_index: 2)

        conn = get(conn, "/api/v2/signet/fills/count")

        assert json_response(conn, 200) == 3
      end

      test "returns filtered count by chain_type", %{conn: conn} do
        insert(:signet_fill, chain_type: :rollup, log_index: 0)
        insert(:signet_fill, chain_type: :host, log_index: 1)
        insert(:signet_fill, chain_type: :rollup, log_index: 2)

        conn = get(conn, "/api/v2/signet/fills/count", %{"chain_type" => "rollup"})

        assert json_response(conn, 200) == 2
      end

      test "returns 0 when no fills exist", %{conn: conn} do
        conn = get(conn, "/api/v2/signet/fills/count")

        assert json_response(conn, 200) == 0
      end
    end

    describe "GET /api/v2/signet/fills/:chain_type/:transaction_hash/:log_index" do
      test "returns single fill by chain type, transaction hash, and log index", %{conn: conn} do
        fill = insert(:signet_fill, chain_type: :rollup, log_index: 5, block_number: 100)

        conn =
          get(
            conn,
            "/api/v2/signet/fills/#{fill.chain_type}/#{fill.transaction_hash}/#{fill.log_index}"
          )

        result = json_response(conn, 200)
        assert result["chain_type"] == to_string(fill.chain_type)
        assert result["transaction_hash"] == to_string(fill.transaction_hash)
        assert result["log_index"] == fill.log_index
        assert result["block_number"] == fill.block_number
      end

      test "returns 404 for non-existent fill", %{conn: conn} do
        fake_hash = "0x" <> String.duplicate("00", 32)

        conn = get(conn, "/api/v2/signet/fills/rollup/#{fake_hash}/0")

        assert json_response(conn, 404)
      end

      test "returns 400 for invalid chain_type", %{conn: conn} do
        fake_hash = "0x" <> String.duplicate("00", 32)

        conn = get(conn, "/api/v2/signet/fills/invalid_chain/#{fake_hash}/0")

        assert %{"message" => message} = json_response(conn, 400)
        assert message =~ "Invalid chain_type"
      end
    end
  end
end
