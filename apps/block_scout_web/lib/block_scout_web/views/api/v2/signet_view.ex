defmodule BlockScoutWeb.API.V2.Signet.SignetView do
  @moduledoc """
  View for rendering Signet order and fill API responses.
  """
  use BlockScoutWeb, :view

  alias Explorer.Chain.Signet
  alias Explorer.Chain.Signet.{Fill, Order}

  @doc """
  Renders a list of orders.
  """
  def render("orders.json", %{orders: orders, next_page_params: next_page_params}) do
    %{
      "items" => Enum.map(orders, &prepare_order/1),
      "next_page_params" => next_page_params
    }
  end

  @doc """
  Renders a list of fills.
  """
  def render("fills.json", %{fills: fills, next_page_params: next_page_params}) do
    %{
      "items" => Enum.map(fills, &prepare_fill/1),
      "next_page_params" => next_page_params
    }
  end

  @doc """
  Renders combined activity (orders and fills).
  """
  def render("activity.json", %{orders: orders, fills: fills, next_page_params: next_page_params}) do
    %{
      "orders" => Enum.map(orders, &prepare_order/1),
      "fills" => Enum.map(fills, &prepare_fill/1),
      "next_page_params" => next_page_params
    }
  end

  @doc """
  Prepares an order for JSON rendering.
  """
  @spec prepare_order(Order.t()) :: map()
  def prepare_order(%Order{} = order) do
    %{
      "order_hash" => compute_order_hash(order),
      "outputs_witness_hash" => compute_outputs_witness_hash(order.outputs_json),
      "deadline" => order.deadline,
      "transaction_hash" => to_string(order.transaction_hash),
      "log_index" => order.log_index,
      "block_number" => order.block_number,
      "inputs" => prepare_inputs(order.inputs_json),
      "outputs" => prepare_outputs(order.outputs_json),
      "status" => to_string(Signet.calculate_order_status(order)),
      "sweep" => prepare_sweep(order)
    }
  end

  @doc """
  Prepares a fill for JSON rendering.
  """
  @spec prepare_fill(Fill.t()) :: map()
  def prepare_fill(%Fill{} = fill) do
    %{
      "outputs_witness_hash" => compute_outputs_witness_hash(fill.outputs_json),
      "transaction_hash" => to_string(fill.transaction_hash),
      "log_index" => fill.log_index,
      "block_number" => fill.block_number,
      "chain_type" => to_string(fill.chain_type),
      "outputs" => prepare_outputs(fill.outputs_json)
    }
  end

  # Private helper functions

  defp prepare_inputs(nil), do: []

  defp prepare_inputs(inputs) when is_list(inputs) do
    Enum.map(inputs, fn input ->
      %{
        "token" => Map.get(input, "token") || Map.get(input, :token),
        "amount" => to_string(Map.get(input, "amount") || Map.get(input, :amount))
      }
    end)
  end

  defp prepare_inputs(_), do: []

  defp prepare_outputs(nil), do: []

  defp prepare_outputs(outputs) when is_list(outputs) do
    Enum.map(outputs, fn output ->
      %{
        "token" => Map.get(output, "token") || Map.get(output, :token),
        "amount" => to_string(Map.get(output, "amount") || Map.get(output, :amount)),
        "recipient" => Map.get(output, "recipient") || Map.get(output, :recipient),
        "chain_id" => Map.get(output, "chainId") || Map.get(output, :chainId) || Map.get(output, "chain_id") || Map.get(output, :chain_id)
      }
    end)
  end

  defp prepare_outputs(_), do: []

  defp prepare_sweep(%Order{sweep_recipient: nil}), do: nil

  defp prepare_sweep(%Order{sweep_recipient: recipient, sweep_token: token, sweep_amount: amount}) do
    %{
      "recipient" => to_string(recipient),
      "token" => if(token, do: to_string(token), else: nil),
      "amount" => if(amount, do: to_string(amount), else: nil)
    }
  end

  # Compute a hash for the order - using transaction_hash + log_index as identifier
  defp compute_order_hash(%Order{transaction_hash: tx_hash, log_index: log_index}) do
    "#{tx_hash}:#{log_index}"
  end

  # Compute outputs witness hash - this is a placeholder
  # In a real implementation, this would compute the actual witness hash
  defp compute_outputs_witness_hash(nil), do: nil

  defp compute_outputs_witness_hash(outputs) when is_list(outputs) do
    # For now, return a deterministic hash based on the outputs
    # A proper implementation would use the actual cryptographic hash
    outputs
    |> :erlang.term_to_binary()
    |> then(fn bin -> :crypto.hash(:sha256, bin) end)
    |> Base.encode16(case: :lower)
    |> then(fn hash -> "0x" <> hash end)
  end

  defp compute_outputs_witness_hash(_), do: nil
end
