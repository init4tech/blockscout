defmodule Indexer.Fetcher.Signet.EventParser do
  @moduledoc """
  Parses Signet Order and Filled events from transaction logs.

  Event signatures and ABI types are sourced from @signet-sh/sdk.
  See `Indexer.Fetcher.Signet.Abi` for topic hash computation.

  ## Event Structures (from @signet-sh/sdk)

  ### Order Event
  ```
  Order(uint256 deadline, Input[] inputs, Output[] outputs)
  ```
  Where:
  - Input = (address token, uint256 amount)
  - Output = (address token, uint256 amount, address recipient, uint32 chainId)

  ### Filled Event
  ```
  Filled(Output[] outputs)
  ```

  ### Sweep Event
  ```
  Sweep(address indexed recipient, address indexed token, uint256 amount)
  ```

  ## Architecture Note

  Orders and fills are indexed independently. Direct correlation between orders
  and their fills is not possible at the indexer level - only block-level
  coordination is available. The data is stored separately for querying and
  analytics purposes.
  """

  require Logger

  alias Indexer.Fetcher.Signet.Abi

  # Size of the Order event header: deadline (32) + inputs_offset (32) + outputs_offset (32)
  @order_header_size 96

  @doc """
  Parse logs from the RollupOrders contract.

  Returns {:ok, {orders, fills}} where orders and fills are lists of maps
  ready for database import.
  """
  @spec parse_rollup_logs([map()]) :: {:ok, {[map()], [map()]}}
  def parse_rollup_logs(logs) when is_list(logs) do
    {orders, fills, sweeps} =
      logs
      |> Enum.map(&normalize_log/1)
      |> Enum.reduce({[], [], []}, &classify_and_parse_log/2)

    orders_with_sweeps = associate_sweeps_with_orders(orders, sweeps)

    {:ok, {Enum.reverse(orders_with_sweeps), Enum.reverse(fills)}}
  end

  @doc """
  Parse Filled events from the HostOrders contract.

  Returns {:ok, fills} where fills is a list of maps ready for database import.
  """
  @spec parse_host_filled_logs([map()]) :: {:ok, [map()]}
  def parse_host_filled_logs(logs) when is_list(logs) do
    filled_topic = Abi.filled_event_topic()

    fills =
      logs
      |> Enum.map(&normalize_log/1)
      |> Enum.filter(&(Enum.at(&1.topics, 0) == filled_topic))
      |> Enum.flat_map(&parse_host_fill_log/1)

    {:ok, fills}
  end

  defp parse_host_fill_log(log) do
    case parse_filled_event(log) do
      {:ok, fill} ->
        [fill]

      {:error, reason} ->
        Logger.warning("Failed to parse host Filled event: #{inspect(reason)}")
        []
    end
  end

  # Normalize log keys from JSON-RPC string keys or Elixir atom keys into a
  # consistent atom-keyed map. Called once at the entry point so all downstream
  # functions work with a single format.
  defp normalize_log(log) when is_map(log) do
    %{
      topics: Map.get(log, "topics") || Map.get(log, :topics) || [],
      data: Map.get(log, "data") || Map.get(log, :data) || "",
      transaction_hash: Map.get(log, "transactionHash") || Map.get(log, :transaction_hash),
      block_number: Map.get(log, "blockNumber") || Map.get(log, :block_number),
      log_index: Map.get(log, "logIndex") || Map.get(log, :log_index)
    }
  end

  defp classify_and_parse_log(log, {orders_acc, fills_acc, sweeps_acc}) do
    topic = Enum.at(log.topics, 0)

    cond do
      topic == Abi.order_event_topic() ->
        collect_parsed(parse_order_event(log), "Order", orders_acc, fills_acc, sweeps_acc, :order)

      topic == Abi.filled_event_topic() ->
        collect_parsed(parse_filled_event(log), "Filled", orders_acc, fills_acc, sweeps_acc, :fill)

      topic == Abi.sweep_event_topic() ->
        collect_parsed(parse_sweep_event(log), "Sweep", orders_acc, fills_acc, sweeps_acc, :sweep)

      true ->
        {orders_acc, fills_acc, sweeps_acc}
    end
  end

  defp collect_parsed({:ok, item}, _label, orders, fills, sweeps, :order),
    do: {[item | orders], fills, sweeps}

  defp collect_parsed({:ok, item}, _label, orders, fills, sweeps, :fill),
    do: {orders, [item | fills], sweeps}

  defp collect_parsed({:ok, item}, _label, orders, fills, sweeps, :sweep),
    do: {orders, fills, [item | sweeps]}

  defp collect_parsed({:error, reason}, label, orders, fills, sweeps, _slot) do
    Logger.warning("Failed to parse #{label} event: #{inspect(reason)}")
    {orders, fills, sweeps}
  end

  # Parse Order event: Order(uint256 deadline, Input[] inputs, Output[] outputs)
  defp parse_order_event(log) do
    data = decode_hex_data(log.data)

    with {:ok, {deadline, inputs, outputs}} <- decode_order_data(data),
         {:ok, block_number} <- parse_block_number(log),
         {:ok, log_index} <- parse_log_index(log) do
      {:ok,
       %{
         deadline: deadline,
         block_number: block_number,
         transaction_hash: format_transaction_hash(log.transaction_hash),
         log_index: log_index,
         inputs_json: Jason.encode!(format_inputs(inputs)),
         outputs_json: Jason.encode!(format_outputs(outputs))
       }}
    end
  end

  # Parse Filled event: Filled(Output[] outputs)
  defp parse_filled_event(log) do
    data = decode_hex_data(log.data)

    with {:ok, outputs} <- decode_filled_data(data),
         {:ok, block_number} <- parse_block_number(log),
         {:ok, log_index} <- parse_log_index(log) do
      {:ok,
       %{
         block_number: block_number,
         transaction_hash: format_transaction_hash(log.transaction_hash),
         log_index: log_index,
         outputs_json: Jason.encode!(format_outputs(outputs))
       }}
    end
  end

  # Parse Sweep event: Sweep(address indexed recipient, address indexed token, uint256 amount)
  defp parse_sweep_event(log) do
    data = decode_hex_data(log.data)

    with {:ok, amount} <- decode_sweep_data(data) do
      {:ok,
       %{
         transaction_hash: format_transaction_hash(log.transaction_hash),
         recipient: decode_indexed_address(Enum.at(log.topics, 1)),
         token: decode_indexed_address(Enum.at(log.topics, 2)),
         amount: amount
       }}
    end
  end

  # ABI decoders

  defp decode_order_data(data) when is_binary(data) and byte_size(data) >= @order_header_size do
    <<deadline::unsigned-big-integer-size(256), inputs_offset::unsigned-big-integer-size(256),
      outputs_offset::unsigned-big-integer-size(256), rest::binary>> = data

    # ABI offsets are from the start of the data payload; subtract the header
    # size to get the position within `rest` (which starts after the header).
    inputs_data =
      binary_part(rest, inputs_offset - @order_header_size, byte_size(rest) - inputs_offset + @order_header_size)

    inputs = decode_input_array(inputs_data)

    outputs_data =
      binary_part(rest, outputs_offset - @order_header_size, byte_size(rest) - outputs_offset + @order_header_size)

    outputs = decode_output_array(outputs_data)

    {:ok, {deadline, inputs, outputs}}
  rescue
    e ->
      Logger.error("Error decoding Order data: #{inspect(e)}")
      {:error, :decode_failed}
  end

  defp decode_order_data(_), do: {:error, :invalid_data}

  defp decode_filled_data(data) when is_binary(data) and byte_size(data) >= 32 do
    <<_offset::unsigned-big-integer-size(256), rest::binary>> = data
    {:ok, decode_output_array(rest)}
  rescue
    e ->
      Logger.error("Error decoding Filled data: #{inspect(e)}")
      {:error, :decode_failed}
  end

  defp decode_filled_data(_), do: {:error, :invalid_data}

  defp decode_sweep_data(<<amount::unsigned-big-integer-size(256)>>), do: {:ok, amount}

  defp decode_sweep_data(_), do: {:error, :invalid_data}

  # Array decoders

  defp decode_input_array(<<length::unsigned-big-integer-size(256), rest::binary>>) do
    decode_inputs(rest, length, [])
  end

  defp decode_inputs(_data, 0, acc), do: Enum.reverse(acc)

  defp decode_inputs(
         <<_padding::binary-size(12), token::binary-size(20), amount::unsigned-big-integer-size(256), rest::binary>>,
         count,
         acc
       ) do
    decode_inputs(rest, count - 1, [{token, amount} | acc])
  end

  defp decode_output_array(<<length::unsigned-big-integer-size(256), rest::binary>>) do
    decode_outputs(rest, length, [])
  end

  defp decode_outputs(_data, 0, acc), do: Enum.reverse(acc)

  defp decode_outputs(
         <<_padding1::binary-size(12), token::binary-size(20), amount::unsigned-big-integer-size(256),
           _padding2::binary-size(12), recipient::binary-size(20), _padding3::binary-size(28),
           chain_id::unsigned-big-integer-size(32), rest::binary>>,
         count,
         acc
       ) do
    decode_outputs(rest, count - 1, [{token, amount, recipient, chain_id} | acc])
  end

  # Sweep association

  defp associate_sweeps_with_orders(orders, sweeps) do
    sweeps_by_tx = Enum.group_by(sweeps, & &1.transaction_hash)

    Enum.map(orders, fn order ->
      case Map.get(sweeps_by_tx, order.transaction_hash) do
        [sweep] ->
          attach_sweep(order, sweep)

        [sweep | rest] ->
          Logger.warning("Multiple sweeps (#{length(rest) + 1}) for tx #{order.transaction_hash}, using first")

          attach_sweep(order, sweep)

        _ ->
          order
      end
    end)
  end

  defp attach_sweep(order, sweep) do
    Map.merge(order, %{
      sweep_recipient: sweep.recipient,
      sweep_token: sweep.token,
      sweep_amount: sweep.amount
    })
  end

  # Formatters

  defp format_inputs(inputs) do
    Enum.map(inputs, fn {token, amount} ->
      %{"token" => format_address(token), "amount" => Integer.to_string(amount)}
    end)
  end

  defp format_outputs(outputs) do
    Enum.map(outputs, fn {token, amount, recipient, chain_id} ->
      %{
        "token" => format_address(token),
        "amount" => Integer.to_string(amount),
        "recipient" => format_address(recipient),
        "chainId" => chain_id
      }
    end)
  end

  defp format_address(bytes) when is_binary(bytes) and byte_size(bytes) == 20 do
    "0x" <> Base.encode16(bytes, case: :lower)
  end

  defp format_transaction_hash("0x" <> _ = hash), do: hash
  defp format_transaction_hash(bytes) when is_binary(bytes), do: "0x" <> Base.encode16(bytes, case: :lower)
  defp format_transaction_hash(_), do: nil

  # Field parsers

  defp decode_hex_data("0x" <> hex), do: Base.decode16!(hex, case: :mixed)
  defp decode_hex_data(raw) when is_binary(raw), do: raw
  defp decode_hex_data(_), do: <<>>

  defp decode_indexed_address("0x" <> hex) do
    address_hex = String.slice(hex, -40, 40)
    Base.decode16!(address_hex, case: :mixed)
  end

  defp decode_indexed_address(bytes) when is_binary(bytes) and byte_size(bytes) == 32 do
    binary_part(bytes, 12, 20)
  end

  defp decode_indexed_address(_), do: nil

  defp parse_block_number(%{block_number: "0x" <> hex}) do
    case Integer.parse(hex, 16) do
      {num, ""} -> {:ok, num}
      _ -> {:error, {:invalid_block_number, "0x" <> hex}}
    end
  end

  defp parse_block_number(%{block_number: num}) when is_integer(num), do: {:ok, num}
  defp parse_block_number(%{block_number: other}), do: {:error, {:invalid_block_number, other}}

  defp parse_log_index(%{log_index: "0x" <> hex}) do
    case Integer.parse(hex, 16) do
      {num, ""} -> {:ok, num}
      _ -> {:error, {:invalid_log_index, "0x" <> hex}}
    end
  end

  defp parse_log_index(%{log_index: num}) when is_integer(num), do: {:ok, num}
  defp parse_log_index(%{log_index: other}), do: {:error, {:invalid_log_index, other}}
end
