defmodule Explorer.Chain.Signet do
  @moduledoc """
  Query functions for Signet orders and fills.
  """

  import Ecto.Query

  alias Explorer.{Chain, PagingOptions, Repo}
  alias Explorer.Chain.Signet.{Fill, Order}

  @default_paging_options %PagingOptions{page_size: 50}

  @doc """
  Fetches orders by block number with pagination support.
  """
  @spec orders_by_block(non_neg_integer(), keyword()) :: [Order.t()]
  def orders_by_block(block_number, options \\ []) do
    paging_options = Keyword.get(options, :paging_options, @default_paging_options)
    api? = Keyword.get(options, :api?, false)

    page_size = paging_options.page_size + 1

    Order
    |> where([o], o.block_number == ^block_number)
    |> order_by([o], [asc: o.log_index])
    |> Chain.page_signet_orders(paging_options)
    |> limit(^page_size)
    |> select_repo(api?).all()
  end

  @doc """
  Fetches fills by block number with pagination support.
  """
  @spec fills_by_block(non_neg_integer(), keyword()) :: [Fill.t()]
  def fills_by_block(block_number, options \\ []) do
    paging_options = Keyword.get(options, :paging_options, @default_paging_options)
    api? = Keyword.get(options, :api?, false)

    page_size = paging_options.page_size + 1

    Fill
    |> where([f], f.block_number == ^block_number)
    |> order_by([f], [asc: f.log_index])
    |> Chain.page_signet_fills(paging_options)
    |> limit(^page_size)
    |> select_repo(api?).all()
  end

  @doc """
  Fetches orders by transaction hash with pagination support.
  """
  @spec orders_by_transaction(Explorer.Chain.Hash.Full.t(), keyword()) :: [Order.t()]
  def orders_by_transaction(transaction_hash, options \\ []) do
    paging_options = Keyword.get(options, :paging_options, @default_paging_options)
    api? = Keyword.get(options, :api?, false)

    page_size = paging_options.page_size + 1

    Order
    |> where([o], o.transaction_hash == ^transaction_hash)
    |> order_by([o], [asc: o.log_index])
    |> Chain.page_signet_orders(paging_options)
    |> limit(^page_size)
    |> select_repo(api?).all()
  end

  @doc """
  Fetches fills by transaction hash with pagination support.
  """
  @spec fills_by_transaction(Explorer.Chain.Hash.Full.t(), keyword()) :: [Fill.t()]
  def fills_by_transaction(transaction_hash, options \\ []) do
    paging_options = Keyword.get(options, :paging_options, @default_paging_options)
    api? = Keyword.get(options, :api?, false)

    page_size = paging_options.page_size + 1

    Fill
    |> where([f], f.transaction_hash == ^transaction_hash)
    |> order_by([f], [asc: f.log_index])
    |> Chain.page_signet_fills(paging_options)
    |> limit(^page_size)
    |> select_repo(api?).all()
  end

  @doc """
  Calculates the status of an order based on deadline and fill status.
  Returns :filled, :pending, or :expired.
  """
  @spec calculate_order_status(Order.t()) :: :filled | :pending | :expired
  def calculate_order_status(%Order{} = order) do
    # Check if there are any fills for this order by matching outputs_witness_hash
    # For now, we'll use a simple deadline-based check
    # A more complete implementation would query fills and match by outputs
    now = DateTime.utc_now() |> DateTime.to_unix()

    cond do
      order.deadline < now -> :expired
      true -> :pending
    end
  end

  defp select_repo(true), do: Repo.replica()
  defp select_repo(_), do: Repo
end
