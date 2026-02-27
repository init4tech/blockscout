defmodule BlockScoutWeb.GraphQL.Signet.QueryFields do
  @moduledoc """
  Query fields for the Signet schema.
  """

  alias BlockScoutWeb.GraphQL.Signet.Resolvers.{Fill, Order}

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema, :modern

  defmacro generate do
    quote do
      @desc "Gets a Signet order by transaction hash and log index."
      field :signet_order, :signet_order do
        arg(:transaction_hash, non_null(:full_hash))
        arg(:log_index, non_null(:integer))

        resolve(&Order.get_by/3)
      end

      @desc "Gets Signet orders with pagination."
      connection field(:signet_orders, node_type: :signet_order) do
        arg(:count, :integer)
        arg(:block_number_gte, :integer)
        arg(:block_number_lte, :integer)

        resolve(&Order.list/3)

        complexity(fn
          %{first: first}, child_complexity -> first * child_complexity
          %{last: last}, child_complexity -> last * child_complexity
          %{}, _child_complexity -> 0
        end)
      end

      @desc "Gets a Signet fill by chain type, transaction hash, and log index."
      field :signet_fill, :signet_fill do
        arg(:chain_type, non_null(:string))
        arg(:transaction_hash, non_null(:full_hash))
        arg(:log_index, non_null(:integer))

        resolve(&Fill.get_by/3)
      end

      @desc "Gets Signet fills with pagination."
      connection field(:signet_fills, node_type: :signet_fill) do
        arg(:count, :integer)
        arg(:chain_type, :string)
        arg(:block_number_gte, :integer)
        arg(:block_number_lte, :integer)

        resolve(&Fill.list/3)

        complexity(fn
          %{first: first}, child_complexity -> first * child_complexity
          %{last: last}, child_complexity -> last * child_complexity
          %{}, _child_complexity -> 0
        end)
      end
    end
  end
end
