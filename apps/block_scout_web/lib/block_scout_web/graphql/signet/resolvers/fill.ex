defmodule BlockScoutWeb.GraphQL.Signet.Resolvers.Fill do
  @moduledoc """
  Resolvers for Signet fills, used in the Signet GraphQL schema.
  """

  alias Absinthe.Relay.Connection
  alias Explorer.Chain
  alias Explorer.GraphQL.Signet, as: GraphQL
  alias Explorer.Repo

  @doc """
  Gets a single fill by chain type, transaction hash, and log index.
  """
  def get_by(_parent, %{chain_type: chain_type_string, transaction_hash: hash_string, log_index: log_index}, _resolution) do
    with {:ok, hash} <- Chain.string_to_full_hash(hash_string),
         {:ok, chain_type} <- parse_chain_type(chain_type_string) do
      case GraphQL.get_fill(chain_type, hash, log_index) do
        nil -> {:error, "Fill not found"}
        fill -> {:ok, fill}
      end
    end
  end

  @doc """
  Lists fills with optional filters and pagination.
  """
  def list(_parent, args, _resolution) do
    args
    |> maybe_parse_chain_type_filter()
    |> GraphQL.fills_query()
    |> Connection.from_query(&Repo.all/1, args, options(args))
  end

  defp parse_chain_type("rollup"), do: {:ok, :rollup}
  defp parse_chain_type("host"), do: {:ok, :host}
  defp parse_chain_type(_), do: {:error, "Invalid chain_type. Must be 'rollup' or 'host'"}

  defp maybe_parse_chain_type_filter(%{chain_type: chain_type_string} = args) do
    case parse_chain_type(chain_type_string) do
      {:ok, chain_type} -> Map.put(args, :chain_type, chain_type)
      {:error, _} -> args
    end
  end

  defp maybe_parse_chain_type_filter(args), do: args

  defp options(%{before: _}), do: []
  defp options(%{count: count}), do: [count: count]
  defp options(_), do: []
end
