if Application.compile_env(:explorer, :chain_type) == :signet do
  defmodule BlockScoutWeb.GraphQL.Signet.SignetFillsTest do
    use BlockScoutWeb.ConnCase

    @moduletag :signet

    describe "signet_fill query" do
      test "returns fill by chain type, transaction hash, and log index", %{conn: conn} do
        fill = insert(:signet_fill, chain_type: :rollup, log_index: 0)

        query = """
        query ($chain_type: String!, $transaction_hash: FullHash!, $log_index: Int!) {
          signet_fill(chain_type: $chain_type, transaction_hash: $transaction_hash, log_index: $log_index) {
            chain_type
            transaction_hash
            log_index
            block_number
            outputs_json
          }
        }
        """

        variables = %{
          "chain_type" => "rollup",
          "transaction_hash" => to_string(fill.transaction_hash),
          "log_index" => fill.log_index
        }

        conn = post(conn, "/api/v1/graphql", query: query, variables: variables)

        assert %{"data" => %{"signet_fill" => result}} = json_response(conn, 200)
        assert result["chain_type"] == "rollup"
        assert result["transaction_hash"] == to_string(fill.transaction_hash)
        assert result["log_index"] == fill.log_index
        assert result["block_number"] == fill.block_number
        assert result["outputs_json"] == fill.outputs_json
      end

      test "returns host chain fill", %{conn: conn} do
        fill = insert(:signet_fill, chain_type: :host, log_index: 0)

        query = """
        query ($chain_type: String!, $transaction_hash: FullHash!, $log_index: Int!) {
          signet_fill(chain_type: $chain_type, transaction_hash: $transaction_hash, log_index: $log_index) {
            chain_type
            transaction_hash
          }
        }
        """

        variables = %{
          "chain_type" => "host",
          "transaction_hash" => to_string(fill.transaction_hash),
          "log_index" => fill.log_index
        }

        conn = post(conn, "/api/v1/graphql", query: query, variables: variables)

        assert %{"data" => %{"signet_fill" => result}} = json_response(conn, 200)
        assert result["chain_type"] == "host"
      end

      test "returns error for non-existent fill", %{conn: conn} do
        query = """
        query ($chain_type: String!, $transaction_hash: FullHash!, $log_index: Int!) {
          signet_fill(chain_type: $chain_type, transaction_hash: $transaction_hash, log_index: $log_index) {
            transaction_hash
          }
        }
        """

        variables = %{
          "chain_type" => "rollup",
          "transaction_hash" => "0x" <> String.duplicate("00", 32),
          "log_index" => 0
        }

        conn = post(conn, "/api/v1/graphql", query: query, variables: variables)

        assert %{"errors" => [error]} = json_response(conn, 200)
        assert error["message"] =~ "Fill not found"
      end

      test "returns error for invalid chain type", %{conn: conn} do
        fill = insert(:signet_fill, chain_type: :rollup, log_index: 0)

        query = """
        query ($chain_type: String!, $transaction_hash: FullHash!, $log_index: Int!) {
          signet_fill(chain_type: $chain_type, transaction_hash: $transaction_hash, log_index: $log_index) {
            transaction_hash
          }
        }
        """

        variables = %{
          "chain_type" => "invalid",
          "transaction_hash" => to_string(fill.transaction_hash),
          "log_index" => fill.log_index
        }

        conn = post(conn, "/api/v1/graphql", query: query, variables: variables)

        assert %{"errors" => [error]} = json_response(conn, 200)
        assert error["message"] =~ "Invalid chain_type"
      end
    end

    describe "signet_fills query" do
      test "returns paginated fills", %{conn: conn} do
        fill1 = insert(:signet_fill, log_index: 0, block_number: 100, chain_type: :rollup)
        fill2 = insert(:signet_fill, log_index: 1, block_number: 101, chain_type: :host)
        fill3 = insert(:signet_fill, log_index: 2, block_number: 102, chain_type: :rollup)

        query = """
        query ($first: Int) {
          signet_fills(first: $first) {
            edges {
              node {
                transaction_hash
                log_index
                block_number
                chain_type
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

        assert %{"data" => %{"signet_fills" => result}} = json_response(conn, 200)
        assert length(result["edges"]) == 3

        # Fills should be returned in descending block_number order
        block_numbers = Enum.map(result["edges"], & &1["node"]["block_number"])
        assert block_numbers == [fill3.block_number, fill2.block_number, fill1.block_number]
      end

      test "filters by chain_type", %{conn: conn} do
        _fill1 = insert(:signet_fill, log_index: 0, block_number: 100, chain_type: :host)
        fill2 = insert(:signet_fill, log_index: 1, block_number: 101, chain_type: :rollup)
        fill3 = insert(:signet_fill, log_index: 2, block_number: 102, chain_type: :rollup)

        query = """
        query ($first: Int, $chain_type: String) {
          signet_fills(first: $first, chain_type: $chain_type) {
            edges {
              node {
                block_number
                chain_type
              }
            }
          }
        }
        """

        variables = %{"first" => 10, "chain_type" => "rollup"}

        conn = post(conn, "/api/v1/graphql", query: query, variables: variables)

        assert %{"data" => %{"signet_fills" => result}} = json_response(conn, 200)
        assert length(result["edges"]) == 2

        chain_types = Enum.map(result["edges"], & &1["node"]["chain_type"])
        assert Enum.all?(chain_types, &(&1 == "rollup"))

        block_numbers = Enum.map(result["edges"], & &1["node"]["block_number"])
        assert fill2.block_number in block_numbers
        assert fill3.block_number in block_numbers
      end

      test "filters by block_number_gte", %{conn: conn} do
        _fill1 = insert(:signet_fill, log_index: 0, block_number: 100)
        fill2 = insert(:signet_fill, log_index: 1, block_number: 200)
        fill3 = insert(:signet_fill, log_index: 2, block_number: 300)

        query = """
        query ($first: Int, $block_number_gte: Int) {
          signet_fills(first: $first, block_number_gte: $block_number_gte) {
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

        assert %{"data" => %{"signet_fills" => result}} = json_response(conn, 200)
        assert length(result["edges"]) == 2

        block_numbers = Enum.map(result["edges"], & &1["node"]["block_number"])
        assert fill2.block_number in block_numbers
        assert fill3.block_number in block_numbers
      end

      test "filters by block_number_lte", %{conn: conn} do
        fill1 = insert(:signet_fill, log_index: 0, block_number: 100)
        fill2 = insert(:signet_fill, log_index: 1, block_number: 200)
        _fill3 = insert(:signet_fill, log_index: 2, block_number: 300)

        query = """
        query ($first: Int, $block_number_lte: Int) {
          signet_fills(first: $first, block_number_lte: $block_number_lte) {
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

        assert %{"data" => %{"signet_fills" => result}} = json_response(conn, 200)
        assert length(result["edges"]) == 2

        block_numbers = Enum.map(result["edges"], & &1["node"]["block_number"])
        assert fill1.block_number in block_numbers
        assert fill2.block_number in block_numbers
      end

      test "combines chain_type and block range filters", %{conn: conn} do
        _fill1 = insert(:signet_fill, log_index: 0, block_number: 100, chain_type: :rollup)
        fill2 = insert(:signet_fill, log_index: 1, block_number: 200, chain_type: :rollup)
        _fill3 = insert(:signet_fill, log_index: 2, block_number: 200, chain_type: :host)
        _fill4 = insert(:signet_fill, log_index: 3, block_number: 300, chain_type: :rollup)

        query = """
        query ($first: Int, $chain_type: String, $block_number_gte: Int, $block_number_lte: Int) {
          signet_fills(first: $first, chain_type: $chain_type, block_number_gte: $block_number_gte, block_number_lte: $block_number_lte) {
            edges {
              node {
                block_number
                chain_type
              }
            }
          }
        }
        """

        variables = %{
          "first" => 10,
          "chain_type" => "rollup",
          "block_number_gte" => 150,
          "block_number_lte" => 250
        }

        conn = post(conn, "/api/v1/graphql", query: query, variables: variables)

        assert %{"data" => %{"signet_fills" => result}} = json_response(conn, 200)
        assert length(result["edges"]) == 1

        [edge] = result["edges"]
        assert edge["node"]["block_number"] == fill2.block_number
        assert edge["node"]["chain_type"] == "rollup"
      end

      test "returns empty list when no fills match", %{conn: conn} do
        query = """
        query ($first: Int) {
          signet_fills(first: $first) {
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

        assert %{"data" => %{"signet_fills" => result}} = json_response(conn, 200)
        assert result["edges"] == []
      end
    end
  end
end
