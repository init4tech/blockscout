if Application.compile_env(:explorer, :chain_type) == :signet do
  defmodule BlockScoutWeb.GraphQL.Signet.SignetOrdersTest do
    use BlockScoutWeb.ConnCase

    @moduletag :signet

    describe "signet_order query" do
      test "returns order by transaction hash and log index", %{conn: conn} do
        order = insert(:signet_order, log_index: 0)

        query = """
        query ($transaction_hash: FullHash!, $log_index: Int!) {
          signet_order(transaction_hash: $transaction_hash, log_index: $log_index) {
            transaction_hash
            log_index
            block_number
            deadline
            inputs_json
            outputs_json
          }
        }
        """

        variables = %{
          "transaction_hash" => to_string(order.transaction_hash),
          "log_index" => order.log_index
        }

        conn = post(conn, "/api/v1/graphql", query: query, variables: variables)

        assert %{"data" => %{"signet_order" => result}} = json_response(conn, 200)
        assert result["transaction_hash"] == to_string(order.transaction_hash)
        assert result["log_index"] == order.log_index
        assert result["block_number"] == order.block_number
        assert result["deadline"] == order.deadline
        assert result["inputs_json"] == order.inputs_json
        assert result["outputs_json"] == order.outputs_json
      end

      test "returns error for non-existent order", %{conn: conn} do
        query = """
        query ($transaction_hash: FullHash!, $log_index: Int!) {
          signet_order(transaction_hash: $transaction_hash, log_index: $log_index) {
            transaction_hash
          }
        }
        """

        variables = %{
          "transaction_hash" => "0x" <> String.duplicate("00", 32),
          "log_index" => 0
        }

        conn = post(conn, "/api/v1/graphql", query: query, variables: variables)

        assert %{"errors" => [error]} = json_response(conn, 200)
        assert error["message"] =~ "Order not found"
      end

      test "returns error for invalid transaction hash", %{conn: conn} do
        query = """
        query ($transaction_hash: FullHash!, $log_index: Int!) {
          signet_order(transaction_hash: $transaction_hash, log_index: $log_index) {
            transaction_hash
          }
        }
        """

        variables = %{
          "transaction_hash" => "invalid",
          "log_index" => 0
        }

        conn = post(conn, "/api/v1/graphql", query: query, variables: variables)

        assert %{"errors" => _errors} = json_response(conn, 200)
      end
    end

    describe "signet_orders query" do
      test "returns paginated orders", %{conn: conn} do
        order1 = insert(:signet_order, log_index: 0, block_number: 100)
        order2 = insert(:signet_order, log_index: 1, block_number: 101)
        order3 = insert(:signet_order, log_index: 2, block_number: 102)

        query = """
        query ($first: Int) {
          signet_orders(first: $first) {
            edges {
              node {
                transaction_hash
                log_index
                block_number
              }
            }
            pageInfo {
              hasNextPage
              hasPreviousPage
            }
          }
        }
        """

        variables = %{"first" => 10}

        conn = post(conn, "/api/v1/graphql", query: query, variables: variables)

        assert %{"data" => %{"signet_orders" => result}} = json_response(conn, 200)
        assert length(result["edges"]) == 3

        # Orders should be returned in descending block_number order
        block_numbers = Enum.map(result["edges"], & &1["node"]["block_number"])
        assert block_numbers == [order3.block_number, order2.block_number, order1.block_number]
      end

      test "filters by block_number_gte", %{conn: conn} do
        _order1 = insert(:signet_order, log_index: 0, block_number: 100)
        order2 = insert(:signet_order, log_index: 1, block_number: 200)
        order3 = insert(:signet_order, log_index: 2, block_number: 300)

        query = """
        query ($first: Int, $block_number_gte: Int) {
          signet_orders(first: $first, block_number_gte: $block_number_gte) {
            edges {
              node {
                block_number
              }
            }
          }
        }
        """

        variables = %{"first" => 10, "block_number_gte" => 150}

        conn = post(conn, "/api/v1/graphql", query: query, variables: variables)

        assert %{"data" => %{"signet_orders" => result}} = json_response(conn, 200)
        assert length(result["edges"]) == 2

        block_numbers = Enum.map(result["edges"], & &1["node"]["block_number"])
        assert order2.block_number in block_numbers
        assert order3.block_number in block_numbers
      end

      test "filters by block_number_lte", %{conn: conn} do
        order1 = insert(:signet_order, log_index: 0, block_number: 100)
        order2 = insert(:signet_order, log_index: 1, block_number: 200)
        _order3 = insert(:signet_order, log_index: 2, block_number: 300)

        query = """
        query ($first: Int, $block_number_lte: Int) {
          signet_orders(first: $first, block_number_lte: $block_number_lte) {
            edges {
              node {
                block_number
              }
            }
          }
        }
        """

        variables = %{"first" => 10, "block_number_lte" => 250}

        conn = post(conn, "/api/v1/graphql", query: query, variables: variables)

        assert %{"data" => %{"signet_orders" => result}} = json_response(conn, 200)
        assert length(result["edges"]) == 2

        block_numbers = Enum.map(result["edges"], & &1["node"]["block_number"])
        assert order1.block_number in block_numbers
        assert order2.block_number in block_numbers
      end

      test "filters by block range (gte and lte)", %{conn: conn} do
        _order1 = insert(:signet_order, log_index: 0, block_number: 100)
        order2 = insert(:signet_order, log_index: 1, block_number: 200)
        _order3 = insert(:signet_order, log_index: 2, block_number: 300)

        query = """
        query ($first: Int, $block_number_gte: Int, $block_number_lte: Int) {
          signet_orders(first: $first, block_number_gte: $block_number_gte, block_number_lte: $block_number_lte) {
            edges {
              node {
                block_number
              }
            }
          }
        }
        """

        variables = %{"first" => 10, "block_number_gte" => 150, "block_number_lte" => 250}

        conn = post(conn, "/api/v1/graphql", query: query, variables: variables)

        assert %{"data" => %{"signet_orders" => result}} = json_response(conn, 200)
        assert length(result["edges"]) == 1

        [edge] = result["edges"]
        assert edge["node"]["block_number"] == order2.block_number
      end

      test "returns empty list when no orders match", %{conn: conn} do
        query = """
        query ($first: Int) {
          signet_orders(first: $first) {
            edges {
              node {
                transaction_hash
              }
            }
          }
        }
        """

        variables = %{"first" => 10}

        conn = post(conn, "/api/v1/graphql", query: query, variables: variables)

        assert %{"data" => %{"signet_orders" => result}} = json_response(conn, 200)
        assert result["edges"] == []
      end
    end
  end
end
