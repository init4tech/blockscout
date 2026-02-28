defmodule BlockScoutWeb.API.V2.SignetView do
  @moduledoc """
  View module for rendering Signet order and fill API responses.
  """
  use BlockScoutWeb, :view

  alias BlockScoutWeb.API.V2.ApiView

  @doc """
  Renders error/text responses.
  """
  def render("message.json", assigns) do
    ApiView.render("message.json", assigns)
  end

  @doc """
  Renders a list of orders with pagination.
  """
  @spec render(binary(), map()) :: map() | non_neg_integer()
  def render("signet_orders.json", %{
        orders: orders,
        next_page_params: next_page_params
      }) do
    orders_out =
      orders
      |> Enum.map(&render_order/1)

    %{
      items: orders_out,
      next_page_params: next_page_params
    }
  end

  @doc """
  Renders the count of orders.
  """
  def render("signet_orders_count.json", %{count: count}) do
    count
  end

  @doc """
  Renders a single order.
  """
  def render("signet_order.json", %{order: order}) do
    render_order(order)
  end

  @doc """
  Renders a list of fills with pagination.
  """
  def render("signet_fills.json", %{
        fills: fills,
        next_page_params: next_page_params
      }) do
    fills_out =
      fills
      |> Enum.map(&render_fill/1)

    %{
      items: fills_out,
      next_page_params: next_page_params
    }
  end

  @doc """
  Renders the count of fills.
  """
  def render("signet_fills_count.json", %{count: count}) do
    count
  end

  @doc """
  Renders a single fill.
  """
  def render("signet_fill.json", %{fill: fill}) do
    render_fill(fill)
  end

  # Private helpers

  defp render_order(order) do
    %{
      "transaction_hash" => to_string(order.transaction_hash),
      "log_index" => order.log_index,
      "block_number" => order.block_number,
      "deadline" => order.deadline,
      "inputs" => parse_json_field(order.inputs_json),
      "outputs" => parse_json_field(order.outputs_json),
      "sweep_recipient" => maybe_to_string(order.sweep_recipient),
      "sweep_token" => maybe_to_string(order.sweep_token),
      "sweep_amount" => maybe_decimal_to_string(order.sweep_amount),
      "inserted_at" => order.inserted_at
    }
  end

  defp render_fill(fill) do
    %{
      "chain_type" => to_string(fill.chain_type),
      "transaction_hash" => to_string(fill.transaction_hash),
      "log_index" => fill.log_index,
      "block_number" => fill.block_number,
      "outputs" => parse_json_field(fill.outputs_json),
      "inserted_at" => fill.inserted_at
    }
  end

  defp parse_json_field(nil), do: nil

  defp parse_json_field(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, parsed} -> parsed
      {:error, _} -> json_string
    end
  end

  defp parse_json_field(other), do: other

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(value), do: to_string(value)

  defp maybe_decimal_to_string(nil), do: nil
  defp maybe_decimal_to_string(%Decimal{} = d), do: Decimal.to_string(d)
  defp maybe_decimal_to_string(value), do: to_string(value)
end
