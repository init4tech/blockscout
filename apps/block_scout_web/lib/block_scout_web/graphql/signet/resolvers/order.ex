defmodule BlockScoutWeb.GraphQL.Signet.Resolvers.Order do
  @moduledoc """
  Resolvers for Signet orders, used in the Signet GraphQL schema.
  """

  alias Absinthe.Relay.Connection
  alias Explorer.Chain
  alias Explorer.GraphQL.Signet, as: GraphQL
  alias Explorer.Repo

  @doc """
  Gets a single order by transaction hash and log index.
  """
  def get_by(_parent, %{transaction_hash: hash_string, log_index: log_index}, _resolution) do
    with {:ok, hash} <- Chain.string_to_full_hash(hash_string) do
      case GraphQL.get_order(hash, log_index) do
        nil -> {:error, "Order not found"}
        order -> {:ok, order}
      end
    end
  end

  @doc """
  Lists orders with optional filters and pagination.
  """
  def list(_parent, args, _resolution) do
    args
    |> GraphQL.orders_query()
    |> Connection.from_query(&Repo.all/1, args, options(args))
  end

  defp options(%{before: _}), do: []
  defp options(%{count: count}), do: [count: count]
  defp options(_), do: []
end
