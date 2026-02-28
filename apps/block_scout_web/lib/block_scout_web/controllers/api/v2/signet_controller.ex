defmodule BlockScoutWeb.API.V2.SignetController do
  @moduledoc """
  Controller for Signet order and fill API endpoints.

  Provides REST API v2 endpoints for querying Signet cross-chain orders and fills.
  """
  use BlockScoutWeb, :controller

  import BlockScoutWeb.Chain,
    only: [
      next_page_params: 5,
      paging_options: 1,
      split_list_by_page: 1
    ]

  alias Explorer.Chain.Hash
  alias Explorer.Chain.Signet.{Fill, Order}
  alias Explorer.GraphQL.Signet, as: SignetQueries
  alias Explorer.{PagingOptions, Repo}

  import Ecto.Query

  action_fallback(BlockScoutWeb.API.V2.FallbackController)

  @doc """
  GET /api/v2/signet/orders

  Lists Signet orders with pagination and optional block range filters.

  ## Query Parameters
    - block_number_gte: minimum block number (optional)
    - block_number_lte: maximum block number (optional)
    - Standard pagination params (page, page_size)
  """
  @spec orders(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def orders(conn, params) do
    options = paging_options(params)

    filter_args = %{}
    |> maybe_add_filter(:block_number_gte, params["block_number_gte"])
    |> maybe_add_filter(:block_number_lte, params["block_number_lte"])

    {orders, next_page} =
      filter_args
      |> SignetQueries.orders_query()
      |> paginate(options)
      |> Repo.all()
      |> split_list_by_page()

    next_page_params =
      next_page_params(
        next_page,
        orders,
        params,
        false,
        fn %Order{block_number: block_number, log_index: log_index} ->
          %{"block_number" => block_number, "log_index" => log_index}
        end
      )

    conn
    |> put_status(200)
    |> render(:signet_orders, %{
      orders: orders,
      next_page_params: next_page_params
    })
  end

  @doc """
  GET /api/v2/signet/orders/count

  Returns the total count of Signet orders.
  """
  @spec orders_count(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def orders_count(conn, _params) do
    count = Repo.aggregate(Order, :count, :transaction_hash)

    conn
    |> put_status(200)
    |> render(:signet_orders_count, %{count: count})
  end

  @doc """
  GET /api/v2/signet/orders/:transaction_hash/:log_index

  Gets a single order by transaction hash and log index.
  """
  @spec order(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def order(conn, %{"transaction_hash" => tx_hash_str, "log_index" => log_index_str}) do
    with {:ok, transaction_hash} <- Hash.Full.cast(tx_hash_str),
         {log_index, ""} <- Integer.parse(log_index_str),
         %Order{} = order <- SignetQueries.get_order(transaction_hash, log_index) do
      conn
      |> put_status(200)
      |> render(:signet_order, %{order: order})
    else
      :error ->
        {:error, :not_found}

      nil ->
        {:error, :not_found}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  GET /api/v2/signet/fills

  Lists Signet fills with pagination and optional filters.

  ## Query Parameters
    - chain_type: "rollup" or "host" (optional)
    - block_number_gte: minimum block number (optional)
    - block_number_lte: maximum block number (optional)
    - Standard pagination params
  """
  @spec fills(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def fills(conn, params) do
    options = paging_options(params)

    filter_args = %{}
    |> maybe_add_chain_type_filter(params["chain_type"])
    |> maybe_add_filter(:block_number_gte, params["block_number_gte"])
    |> maybe_add_filter(:block_number_lte, params["block_number_lte"])

    {fills, next_page} =
      filter_args
      |> SignetQueries.fills_query()
      |> paginate(options)
      |> Repo.all()
      |> split_list_by_page()

    next_page_params =
      next_page_params(
        next_page,
        fills,
        params,
        false,
        fn %Fill{block_number: block_number, log_index: log_index, chain_type: chain_type} ->
          %{"block_number" => block_number, "log_index" => log_index, "chain_type" => chain_type}
        end
      )

    conn
    |> put_status(200)
    |> render(:signet_fills, %{
      fills: fills,
      next_page_params: next_page_params
    })
  end

  @doc """
  GET /api/v2/signet/fills/count

  Returns the total count of Signet fills, optionally filtered by chain type.

  ## Query Parameters
    - chain_type: "rollup" or "host" (optional)
  """
  @spec fills_count(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def fills_count(conn, params) do
    query = from(f in Fill)

    query =
      case params["chain_type"] do
        "rollup" -> from(f in query, where: f.chain_type == :rollup)
        "host" -> from(f in query, where: f.chain_type == :host)
        _ -> query
      end

    count = Repo.aggregate(query, :count, :transaction_hash)

    conn
    |> put_status(200)
    |> render(:signet_fills_count, %{count: count})
  end

  @doc """
  GET /api/v2/signet/fills/:chain_type/:transaction_hash/:log_index

  Gets a single fill by chain type, transaction hash, and log index.
  """
  @spec fill(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def fill(conn, %{
        "chain_type" => chain_type_str,
        "transaction_hash" => tx_hash_str,
        "log_index" => log_index_str
      }) do
    with {:ok, chain_type} <- parse_chain_type(chain_type_str),
         {:ok, transaction_hash} <- Hash.Full.cast(tx_hash_str),
         {log_index, ""} <- Integer.parse(log_index_str),
         %Fill{} = fill <- SignetQueries.get_fill(chain_type, transaction_hash, log_index) do
      conn
      |> put_status(200)
      |> render(:signet_fill, %{fill: fill})
    else
      :error ->
        {:error, :not_found}

      nil ->
        {:error, :not_found}

      {:error, :invalid_chain_type} ->
        conn
        |> put_status(:bad_request)
        |> render(:message, %{message: "Invalid chain_type. Must be 'rollup' or 'host'."})

      _ ->
        {:error, :not_found}
    end
  end

  # Private helpers

  defp parse_chain_type("rollup"), do: {:ok, :rollup}
  defp parse_chain_type("host"), do: {:ok, :host}
  defp parse_chain_type(_), do: {:error, :invalid_chain_type}

  defp maybe_add_filter(args, key, value) when is_binary(value) do
    case Integer.parse(value) do
      {int_val, ""} -> Map.put(args, key, int_val)
      _ -> args
    end
  end

  defp maybe_add_filter(args, _key, _value), do: args

  defp maybe_add_chain_type_filter(args, "rollup"), do: Map.put(args, :chain_type, :rollup)
  defp maybe_add_chain_type_filter(args, "host"), do: Map.put(args, :chain_type, :host)
  defp maybe_add_chain_type_filter(args, _), do: args

  defp paginate(query, %PagingOptions{page_size: page_size}) do
    from(q in query, limit: ^(page_size + 1))
  end

  defp paginate(query, _), do: from(q in query, limit: 51)
end
