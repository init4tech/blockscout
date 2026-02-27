defmodule BlockScoutWeb.GraphQL.Signet.Schema.Types do
  @moduledoc """
  GraphQL types for Signet orders and fills.
  """

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  @desc """
  Represents a Signet cross-chain order from the RollupOrders contract.

  Orders specify inputs (tokens offered by the maker) and outputs (tokens
  expected in return). The chainId in outputs represents the DESTINATION
  chain where assets should be delivered.
  """
  node object(:signet_order, id_fetcher: &signet_order_id_fetcher/2) do
    field(:transaction_hash, :full_hash)
    field(:log_index, :integer)
    field(:block_number, :integer)
    field(:deadline, :integer)
    field(:inputs_json, :string)
    field(:outputs_json, :string)
    field(:sweep_recipient, :address_hash)
    field(:sweep_token, :address_hash)
    field(:sweep_amount, :decimal)
    field(:inserted_at, :datetime)
  end

  @desc """
  Represents a Signet fill event from RollupOrders or HostOrders contracts.

  Fills record the execution of orders. The chainId in outputs represents
  the ORIGIN chain where the order was created, not where the fill occurred.
  """
  node object(:signet_fill, id_fetcher: &signet_fill_id_fetcher/2) do
    field(:chain_type, :string)
    field(:transaction_hash, :full_hash)
    field(:log_index, :integer)
    field(:block_number, :integer)
    field(:outputs_json, :string)
    field(:inserted_at, :datetime)
  end

  connection(node_type: :signet_order)
  connection(node_type: :signet_fill)

  defp signet_order_id_fetcher(%{transaction_hash: transaction_hash, log_index: log_index}, _) do
    Jason.encode!(%{
      transaction_hash: to_string(transaction_hash),
      log_index: log_index
    })
  end

  defp signet_fill_id_fetcher(
         %{chain_type: chain_type, transaction_hash: transaction_hash, log_index: log_index},
         _
       ) do
    Jason.encode!(%{
      chain_type: to_string(chain_type),
      transaction_hash: to_string(transaction_hash),
      log_index: log_index
    })
  end
end
