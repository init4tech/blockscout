defmodule BlockScoutWeb.SignetChannel do
  @moduledoc """
  Establishes pub/sub channel for live updates of Signet related events.
  """
  use BlockScoutWeb, :channel

  def join("signet:new_order", _params, socket) do
    {:ok, %{}, socket}
  end

  def join("signet:new_fill", _params, socket) do
    {:ok, %{}, socket}
  end

  def join("signet:order_updates", _params, socket) do
    {:ok, %{}, socket}
  end
end
