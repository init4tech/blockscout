defmodule BlockScoutWeb.Notifiers.Signet do
  @moduledoc """
  Module to handle and broadcast Signet related events.
  """

  alias BlockScoutWeb.API.V2.SignetView
  alias BlockScoutWeb.Endpoint

  require Logger

  def handle_event({:chain_event, :new_signet_orders, :realtime, orders}) do
    orders
    |> Enum.each(fn order ->
      Endpoint.broadcast("signet:new_order", "new_signet_order", %{
        order: SignetView.render("signet_order.json", %{order: order})
      })
    end)
  end

  def handle_event({:chain_event, :new_signet_fills, :realtime, fills}) do
    fills
    |> Enum.each(fn fill ->
      Endpoint.broadcast("signet:new_fill", "new_signet_fill", %{
        fill: SignetView.render("signet_fill.json", %{fill: fill})
      })
    end)
  end

  def handle_event({:chain_event, :signet_order_updates, :realtime, orders}) do
    orders
    |> Enum.each(fn order ->
      Endpoint.broadcast("signet:order_updates", "signet_order_updated", %{
        order: SignetView.render("signet_order.json", %{order: order})
      })
    end)
  end

  def handle_event(event) do
    Logger.warning("Unknown broadcasted event #{inspect(event)}.")
    nil
  end
end
