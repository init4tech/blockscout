defmodule Explorer.GraphQL.Signet do
  @moduledoc """
  Defines Ecto queries to fetch Signet order and fill data for the GraphQL schema.

  Includes functions to construct queries for orders and fills, supporting
  pagination and filtering by block range and chain type.
  """

  import Ecto.Query, only: [from: 2, order_by: 3, where: 3]

  alias Explorer.Chain.Hash
  alias Explorer.Chain.Signet.{Fill, Order}
  alias Explorer.Repo

  @doc """
  Gets a single order by transaction hash and log index.

  ## Parameters
    - transaction_hash: the full transaction hash
    - log_index: the log index within the transaction

  ## Returns
    - Order struct or nil
  """
  @spec get_order(Hash.Full.t(), integer()) :: Order.t() | nil
  def get_order(transaction_hash, log_index) do
    Repo.one(
      from(o in Order,
        where: o.transaction_hash == ^transaction_hash and o.log_index == ^log_index
      )
    )
  end

  @doc """
  Constructs a query for orders with optional filters.

  ## Parameters
    - args: Map with optional filters:
      - block_number_gte: minimum block number
      - block_number_lte: maximum block number

  ## Returns
    - Ecto query
  """
  @spec orders_query(map()) :: Ecto.Query.t()
  def orders_query(args \\ %{}) do
    from(o in Order, as: :order)
    |> maybe_filter_block_range(args, :order)
    |> order_by([order: o], desc: o.block_number, desc: o.log_index)
  end

  @doc """
  Gets a single fill by chain type, transaction hash, and log index.

  ## Parameters
    - chain_type: :rollup or :host
    - transaction_hash: the full transaction hash
    - log_index: the log index within the transaction

  ## Returns
    - Fill struct or nil
  """
  @spec get_fill(atom(), Hash.Full.t(), integer()) :: Fill.t() | nil
  def get_fill(chain_type, transaction_hash, log_index) do
    Repo.one(
      from(f in Fill,
        where:
          f.chain_type == ^chain_type and
            f.transaction_hash == ^transaction_hash and
            f.log_index == ^log_index
      )
    )
  end

  @doc """
  Constructs a query for fills with optional filters.

  ## Parameters
    - args: Map with optional filters:
      - chain_type: :rollup or :host atom
      - block_number_gte: minimum block number
      - block_number_lte: maximum block number

  ## Returns
    - Ecto query
  """
  @spec fills_query(map()) :: Ecto.Query.t()
  def fills_query(args \\ %{}) do
    from(f in Fill, as: :fill)
    |> maybe_filter_chain_type(args)
    |> maybe_filter_block_range(args, :fill)
    |> order_by([fill: f], desc: f.block_number, desc: f.log_index)
  end

  # Private helper to filter by chain_type
  defp maybe_filter_chain_type(query, %{chain_type: chain_type}) when chain_type in [:rollup, :host] do
    where(query, [fill: f], f.chain_type == ^chain_type)
  end

  defp maybe_filter_chain_type(query, _), do: query

  # Private helper to filter by block range
  defp maybe_filter_block_range(query, args, binding) do
    query
    |> maybe_filter_block_gte(args, binding)
    |> maybe_filter_block_lte(args, binding)
  end

  defp maybe_filter_block_gte(query, %{block_number_gte: block_number}, :order) do
    where(query, [order: o], o.block_number >= ^block_number)
  end

  defp maybe_filter_block_gte(query, %{block_number_gte: block_number}, :fill) do
    where(query, [fill: f], f.block_number >= ^block_number)
  end

  defp maybe_filter_block_gte(query, _, _), do: query

  defp maybe_filter_block_lte(query, %{block_number_lte: block_number}, :order) do
    where(query, [order: o], o.block_number <= ^block_number)
  end

  defp maybe_filter_block_lte(query, %{block_number_lte: block_number}, :fill) do
    where(query, [fill: f], f.block_number <= ^block_number)
  end

  defp maybe_filter_block_lte(query, _, _), do: query
end
