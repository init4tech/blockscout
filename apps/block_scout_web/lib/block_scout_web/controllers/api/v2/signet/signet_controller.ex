defmodule BlockScoutWeb.API.V2.Signet.SignetController do
  @moduledoc """
  Controller for Signet order and fill API endpoints.
  
  Provides endpoints for querying Signet orders and fills by block number
  or transaction hash.
  """
  use BlockScoutWeb, :controller

  import BlockScoutWeb.Chain,
    only: [
      next_page_params: 5,
      paging_options: 1,
      split_list_by_page: 1
    ]

  alias BlockScoutWeb.API.V2.Signet.SignetView
  alias Explorer.Chain.Signet

  @api_true [api?: true]

  action_fallback(BlockScoutWeb.API.V2.FallbackController)

  @doc """
  GET /api/v2/signet/blocks/:block_number/orders
  
  Returns all orders initiated in a specific block.
  """
  def block_orders(conn, %{"block_number" => block_number_string} = params) do
    with {:ok, block_number} <- parse_block_number(block_number_string) do
      full_options =
        @api_true
        |> Keyword.merge(paging_options(params))

      orders_plus_one = Signet.orders_by_block(block_number, full_options)
      {orders, next_page} = split_list_by_page(orders_plus_one)

      next_page_params =
        next_page_params(next_page, orders, params, false, &signet_paging_options/1)

      conn
      |> put_status(200)
      |> put_view(SignetView)
      |> render(:orders, %{orders: orders, next_page_params: next_page_params})
    end
  end

  @doc """
  GET /api/v2/signet/blocks/:block_number/fills
  
  Returns all fills executed in a specific block.
  """
  def block_fills(conn, %{"block_number" => block_number_string} = params) do
    with {:ok, block_number} <- parse_block_number(block_number_string) do
      full_options =
        @api_true
        |> Keyword.merge(paging_options(params))

      fills_plus_one = Signet.fills_by_block(block_number, full_options)
      {fills, next_page} = split_list_by_page(fills_plus_one)

      next_page_params =
        next_page_params(next_page, fills, params, false, &signet_paging_options/1)

      conn
      |> put_status(200)
      |> put_view(SignetView)
      |> render(:fills, %{fills: fills, next_page_params: next_page_params})
    end
  end

  @doc """
  GET /api/v2/signet/blocks/:block_number/activity
  
  Returns combined view of orders and fills for a specific block.
  """
  def block_activity(conn, %{"block_number" => block_number_string} = params) do
    with {:ok, block_number} <- parse_block_number(block_number_string) do
      full_options =
        @api_true
        |> Keyword.merge(paging_options(params))

      orders = Signet.orders_by_block(block_number, full_options)
      fills = Signet.fills_by_block(block_number, full_options)

      conn
      |> put_status(200)
      |> put_view(SignetView)
      |> render(:activity, %{orders: orders, fills: fills, next_page_params: nil})
    end
  end

  @doc """
  GET /api/v2/signet/transactions/:transaction_hash/orders
  
  Returns orders initiated by a specific transaction.
  """
  def transaction_orders(conn, %{"transaction_hash" => tx_hash_string} = params) do
    with {:ok, tx_hash} <- parse_transaction_hash(tx_hash_string) do
      full_options =
        @api_true
        |> Keyword.merge(paging_options(params))

      orders_plus_one = Signet.orders_by_transaction(tx_hash, full_options)
      {orders, next_page} = split_list_by_page(orders_plus_one)

      next_page_params =
        next_page_params(next_page, orders, params, false, &signet_paging_options/1)

      conn
      |> put_status(200)
      |> put_view(SignetView)
      |> render(:orders, %{orders: orders, next_page_params: next_page_params})
    end
  end

  @doc """
  GET /api/v2/signet/transactions/:transaction_hash/fills
  
  Returns fills executed by a specific transaction.
  """
  def transaction_fills(conn, %{"transaction_hash" => tx_hash_string} = params) do
    with {:ok, tx_hash} <- parse_transaction_hash(tx_hash_string) do
      full_options =
        @api_true
        |> Keyword.merge(paging_options(params))

      fills_plus_one = Signet.fills_by_transaction(tx_hash, full_options)
      {fills, next_page} = split_list_by_page(fills_plus_one)

      next_page_params =
        next_page_params(next_page, fills, params, false, &signet_paging_options/1)

      conn
      |> put_status(200)
      |> put_view(SignetView)
      |> render(:fills, %{fills: fills, next_page_params: next_page_params})
    end
  end

  @doc """
  GET /api/v2/signet/transactions/:transaction_hash/activity
  
  Returns combined view of orders and fills for a specific transaction.
  """
  def transaction_activity(conn, %{"transaction_hash" => tx_hash_string} = params) do
    with {:ok, tx_hash} <- parse_transaction_hash(tx_hash_string) do
      full_options =
        @api_true
        |> Keyword.merge(paging_options(params))

      orders = Signet.orders_by_transaction(tx_hash, full_options)
      fills = Signet.fills_by_transaction(tx_hash, full_options)

      conn
      |> put_status(200)
      |> put_view(SignetView)
      |> render(:activity, %{orders: orders, fills: fills, next_page_params: nil})
    end
  end

  # Private functions

  defp parse_block_number(block_number_string) do
    case Integer.parse(block_number_string) do
      {block_number, ""} when block_number >= 0 -> {:ok, block_number}
      _ -> {:error, {:invalid, :number}}
    end
  end

  defp parse_transaction_hash(tx_hash_string) do
    case Explorer.Chain.Hash.Full.cast(tx_hash_string) do
      {:ok, hash} -> {:ok, hash}
      :error -> {:error, {:invalid, :hash}}
    end
  end

  defp signet_paging_options(item) do
    %{
      "log_index" => item.log_index
    }
  end
end
