defmodule Indexer.Fetcher.Signet.Abi do
  @moduledoc """
  ABI event topic hashes for Signet contracts.

  ## Event Signatures

  RollupOrders contract:
  - Order(uint256 deadline, (address token, uint256 amount)[] inputs, (address token, uint256 amount, address recipient, uint32 chainId)[] outputs)
  - Filled((address token, uint256 amount, address recipient, uint32 chainId)[] outputs)
  - Sweep(address indexed recipient, address indexed token, uint256 amount)

  HostOrders contract:
  - Filled((address token, uint256 amount, address recipient, uint32 chainId)[] outputs)
  """

  @order_event_signature "Order(uint256,(address,uint256)[],(address,uint256,address,uint32)[])"
  @filled_event_signature "Filled((address,uint256,address,uint32)[])"
  @sweep_event_signature "Sweep(address,address,uint256)"

  @order_event_topic "0x" <> Base.encode16(ExKeccak.hash_256(@order_event_signature), case: :lower)
  @filled_event_topic "0x" <> Base.encode16(ExKeccak.hash_256(@filled_event_signature), case: :lower)
  @sweep_event_topic "0x" <> Base.encode16(ExKeccak.hash_256(@sweep_event_signature), case: :lower)

  @doc "Returns the keccak256 topic hash for the Order event."
  @spec order_event_topic() :: String.t()
  def order_event_topic, do: @order_event_topic

  @doc "Returns the keccak256 topic hash for the Filled event."
  @spec filled_event_topic() :: String.t()
  def filled_event_topic, do: @filled_event_topic

  @doc "Returns the keccak256 topic hash for the Sweep event."
  @spec sweep_event_topic() :: String.t()
  def sweep_event_topic, do: @sweep_event_topic

  @doc "Returns all event topics for the RollupOrders contract."
  @spec rollup_orders_event_topics() :: [String.t()]
  def rollup_orders_event_topics, do: [@order_event_topic, @filled_event_topic, @sweep_event_topic]

  @doc "Returns all event topics for the HostOrders contract."
  @spec host_orders_event_topics() :: [String.t()]
  def host_orders_event_topics, do: [@filled_event_topic]

  @doc "Returns the event signature string for the Order event."
  @spec order_event_signature() :: String.t()
  def order_event_signature, do: @order_event_signature

  @doc "Returns the event signature string for the Filled event."
  @spec filled_event_signature() :: String.t()
  def filled_event_signature, do: @filled_event_signature

  @doc "Returns the event signature string for the Sweep event."
  @spec sweep_event_signature() :: String.t()
  def sweep_event_signature, do: @sweep_event_signature
end
