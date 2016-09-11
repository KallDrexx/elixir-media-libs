defmodule RtmpSession.ChunkIo do
  @moduledoc """
  This module provider an API for processing the raw binary that makes up
  RTMP chunks (and unpacking the enclosed RTMP message within) and allows
  serializing RTMP messages into binary RTMP chunks  
  """

  alias RtmpSession.RtmpMessage, as: RtmpMessage
  alias RtmpSession.RtmpTime, as: RtmpTime

  require Logger

  defmodule State do
    defstruct receiving_max_chunk_size: 128,
              sending_max_chunk_size: 128,
              received_headers: %{},
              sent_headers: %{},
              current_header: nil,
              unparsed_binary: <<>>,
              incomplete_message: nil
  end

  defmodule Header do
    defstruct type: 0,
              csid: nil,
              timestamp: nil,
              last_timestamp_delta: nil,
              message_length: nil,
              message_type_id: nil,
              message_stream_id: nil
  end

  @spec new() :: %State{}
  def new() do
    %State{}
  end

  @spec set_receiving_max_chunk_size(%State{}, pos_integer()) :: %State{}
  def set_receiving_max_chunk_size(state = %State{}, size) do
    %{state | receiving_max_chunk_size: size}
  end

  @spec set_sending_max_chunk_size(%State{}, pos_integer()) :: %State{}
  def set_sending_max_chunk_size(state = %State{}, size) do
    %{state | sending_max_chunk_size: size}
  end

  @spec deserialize(%State{}, <<>>) :: {%State{}, :incomplete} | {%State{}, :split_message} | {%State{}, %RtmpMessage{}} 
  def deserialize(state = %State{}, binary) when is_binary(binary) do
    do_deserialize(%{state | unparsed_binary: state.unparsed_binary <> binary})
  end

  @spec serialize(%State{}, %RtmpMessage{}, non_neg_integer(), boolean()) :: {%State{}, iodata()}
  def serialize(state = %State{}, message = %RtmpMessage{}, csid, force_uncompressed \\ false) do
    do_serialize(state, message, csid, force_uncompressed)    
  end

  ## Deserialization functions

  defp do_deserialize(state = %State{}) do
    case state.unparsed_binary do
      <<0::2, 0::6, csid::8, 16777215::3 * 8, size::3 * 8, message_type_id::8, sid::size(4)-unit(8)-little, timestamp::4 * 8, rest::binary>> -> 
        deserialize_header(state, 0, csid - 64, timestamp, size, message_type_id, sid, rest)

      <<0::2, 0::6, csid::8, timestamp::3 * 8, size::3 * 8, message_type_id::8, sid::size(4)-unit(8)-little, rest::binary>> ->
        deserialize_header(state, 0, csid - 64, timestamp, size, message_type_id, sid, rest)

      <<0::2, 1::6, csid::16, 16777215::3 * 8, size::3 * 8, message_type_id::8, sid::size(4)-unit(8)-little, timestamp::4 * 8, rest::binary>> ->
        deserialize_header(state, 0, csid - 64, timestamp, size, message_type_id, sid, rest)

      <<0::2, 1::6, csid::16, timestamp::3 * 8, size::3 * 8, message_type_id::8, sid::size(4)-unit(8)-little, rest::binary>> ->
        deserialize_header(state, 0, csid - 64, timestamp, size, message_type_id, sid, rest)

      <<0::2, csid::6, 16777215::3 * 8, size::3 * 8, message_type_id::8, sid::size(4)-unit(8)-little, timestamp::4 * 8, rest::binary>> ->
        deserialize_header(state, 0, csid, timestamp, size, message_type_id, sid, rest)

      <<0::2, csid::6, timestamp::3 * 8, size::3 * 8, message_type_id::8, sid::size(4)-unit(8)-little, rest::binary>> ->
        deserialize_header(state, 0, csid, timestamp, size, message_type_id, sid, rest)

      <<1::2, 0::6, csid::8, 16777215::3 * 8, size::3 * 8, message_type_id::8, timestamp::4 * 8, rest::binary>> -> 
        deserialize_header(state, 1, csid - 64, timestamp, size, message_type_id, rest)

      <<1::2, 0::6, csid::8, timestamp::3 * 8, size::3 * 8, message_type_id::8, rest::binary>> -> 
        deserialize_header(state, 1, csid - 64, timestamp, size, message_type_id, rest)
        
      <<1::2, 1::6, csid::16, 16777215::3 * 8, size::3 * 8, message_type_id::8, timestamp::4 * 8, rest::binary>> -> 
        deserialize_header(state, 1, csid - 64, timestamp, size, message_type_id, rest)
        
      <<1::2, 1::6, csid::16, timestamp::3 * 8, size::3 * 8, message_type_id::8, rest::binary>> -> 
        deserialize_header(state, 1, csid - 64, timestamp, size, message_type_id, rest)
        
      <<1::2, csid::6, 16777215::3 * 8, size::3 * 8, message_type_id::8, timestamp::4 * 8, rest::binary>> ->
        deserialize_header(state, 1, csid, timestamp, size, message_type_id, rest)
        
      <<1::2, csid::6, timestamp::3 * 8, size::3 * 8, message_type_id::8, rest::binary>> -> 
        deserialize_header(state, 1, csid, timestamp, size, message_type_id, rest)
        
      <<2::2, 0::6, csid::8, 16777215::3 * 8, timestamp::4 * 8, rest::binary>> -> 
        deserialize_header(state, 2, csid - 64, timestamp, rest)

      <<2::2, 0::6, csid::8, timestamp::3 * 8, rest::binary>> -> 
        deserialize_header(state, 2, csid - 64, timestamp, rest)
        
      <<2::2, 1::6, csid::16, 16777215::3 * 8, timestamp::4 * 8, rest::binary>> -> 
        deserialize_header(state, 2, csid - 64, timestamp, rest)
        
      <<2::2, 1::6, csid::16, timestamp::3 * 8, rest::binary>> -> 
        deserialize_header(state, 2, csid - 64, timestamp, rest)
        
      <<2::2, csid::6, 16777215::3 * 8, timestamp::4 * 8, rest::binary>> -> 
        deserialize_header(state, 2, csid, timestamp, rest)
        
      <<2::2, csid::6, timestamp::3 * 8, rest::binary>> -> 
        deserialize_header(state, 2, csid, timestamp, rest)        

      <<3::2, 0::6, csid::8, rest::binary>> -> deserialize_header(state, 3, csid - 64, rest)
      <<3::2, 1::6, csid::16, rest::binary>> -> deserialize_header(state, 3, csid - 64, rest)
      <<3::2, csid::6, rest::binary>> -> deserialize_header(state, 3, csid, rest)

      _ ->
        if byte_size(state.unparsed_binary) > state.receiving_max_chunk_size * 10 do
          raise("Too much unparsed binary with the header not matching any known formats")
        end

        {state, :incomplete}
    end
  end
   
  defp deserialize_header(state, 0, csid, timestamp, length, message_type_id, sid, remaining_binary) do
    if byte_size(remaining_binary) < get_expected_chunk_size(state, length) do
      {state, :incomplete}
    else
      header = %Header {
        csid: csid,
        timestamp: timestamp,
        last_timestamp_delta: 0,
        message_length: length,
        message_type_id: message_type_id,
        message_stream_id: sid
      }

      new_state = %{state | received_headers: Map.put(state.received_headers, csid, header)}
      deserialize_message(new_state, timestamp, message_type_id, sid, length, remaining_binary)
    end
  end

  defp deserialize_header(state, 1, csid, delta, length, type_id, remaining_binary) do
    if byte_size(remaining_binary) < get_expected_chunk_size(state, length) do
      {state, :incomplete}
    else
      previous_header = get_previous_header!(state.received_headers, csid, 1)
      updated_header = %{previous_header |
        timestamp: RtmpTime.apply_delta(previous_header.timestamp, delta),
        last_timestamp_delta: delta,
        message_length: length,
        message_type_id: type_id
      }

      new_state = %{state | received_headers: Map.put(state.received_headers, csid, updated_header)}
      deserialize_message(new_state, updated_header.timestamp, type_id, updated_header.message_stream_id, length, remaining_binary)
    end
  end

  defp deserialize_header(state, 2, csid, delta, remaining_binary) do
    previous_header = get_previous_header!(state.received_headers, csid, 2)
    if byte_size(remaining_binary) < get_expected_chunk_size(state, previous_header.message_length) do
      {state, :incomplete}
    else
      updated_header = %{previous_header |
        timestamp: RtmpTime.apply_delta(previous_header.timestamp, delta),
        last_timestamp_delta: delta 
      }

      new_state = %{state | received_headers: Map.put(state.received_headers, csid, updated_header)}
      deserialize_message(new_state, 
        updated_header.timestamp, 
        updated_header.message_type_id, 
        updated_header.message_stream_id, 
        updated_header.message_length, 
        remaining_binary)
    end
  end

  defp deserialize_header(state, 3, csid, remaining_binary) do
    previous_header = get_previous_header!(state.received_headers, csid, 3)
    if byte_size(remaining_binary) < get_expected_chunk_size(state, previous_header.message_length) do
      {state, :incomplete}
    else
      updated_header = %{previous_header |
        timestamp: RtmpTime.apply_delta(previous_header.timestamp, previous_header.last_timestamp_delta),
      }

      new_state = %{state | received_headers: Map.put(state.received_headers, csid, updated_header)}

      deserialize_message(new_state, 
        updated_header.timestamp, 
        updated_header.message_type_id, 
        updated_header.message_stream_id, 
        updated_header.message_length, 
        remaining_binary)
    end
  end

  defp deserialize_message(state, timestamp, type_id, stream_id, message_length, remaining_binary) do
    current_message = if state.incomplete_message != nil do
      state.incomplete_message
    else
      %RtmpMessage{
        timestamp: timestamp,
        message_type_id: type_id,
        stream_id: stream_id
      }
    end

    payload_so_far = byte_size(current_message.payload)
    length_remaining = message_length - payload_so_far
    chunk_payload_length = Enum.min([length_remaining, state.receiving_max_chunk_size])

    deserialize_payload(state, chunk_payload_length, message_length, current_message, remaining_binary)
  end

  defp deserialize_payload(state, chunk_payload_length, _full_length, _incomplete_message, remaining_binary) 
    when byte_size(remaining_binary) < chunk_payload_length do
    
    {state, :incomplete}
  end

  defp deserialize_payload(state, chunk_payload_length, full_length, incomplete_message, remaining_binary) do
    <<payload::size(chunk_payload_length)-binary, rest::binary>> = remaining_binary

    updated_message = %{incomplete_message | payload: incomplete_message.payload <> payload}
    if byte_size(updated_message.payload) == full_length do
      new_state = %{state |
        unparsed_binary: rest,
        incomplete_message: nil
      }

      {new_state, updated_message}
    else
      new_state = %{state |
        unparsed_binary: rest,
        incomplete_message: updated_message
      }

      {new_state, :split_message}
    end
  end 

  defp get_previous_header!(previous_headers, csid, current_chunk_type) do
    case Map.fetch(previous_headers, csid) do
      {:ok, value} -> value
      :error -> raise "Received type #{current_chunk_type} chunk header for chunk stream id #{csid} without receiving a type 0 chunk first"
    end
  end

  defp get_expected_chunk_size(state, message_length) do
    if message_length < state.receiving_max_chunk_size do
      message_length
    else
      bytes_received_so_far = case state.incomplete_message do
        nil -> 0
        %RtmpMessage{payload: payload} -> byte_size(payload)
      end

      bytes_remaining = message_length - bytes_received_so_far
      if bytes_remaining < state.receiving_max_chunk_size do
        bytes_remaining
      else
        state.receiving_max_chunk_size
      end
    end
  end

  ## Serialization Functions  

  defp do_serialize(state, message, csid, force_uncompressed) do
    case split_message_to_chunk_size(state, message, [], 0) do
      {size, [x]} -> 
        serialize_message(state, x, csid, force_uncompressed, size)

      {size, [x | rest]} -> 
        serialize_split_message(state, [x | rest], csid, true, <<>>, size) 
    end
  end

  defp serialize_split_message(state, messages, csid, force_uncompressed, binary, total_payload_size) do
    case messages do
      [] -> {state, binary}
      [x | rest] -> 
        {new_state, new_binary} = serialize_message(state, x, csid, force_uncompressed, total_payload_size)
        serialize_split_message(new_state, rest, csid, false, binary <> new_binary, total_payload_size)
    end
  end

  defp serialize_message(state, message, csid, force_uncompressed, total_payload_size) do
    header = %Header{
      type: 0,
      csid: csid,
      timestamp: message.timestamp, # TODO: convert to rtmp timestamp
      last_timestamp_delta: 0,
      message_length: total_payload_size,
      message_type_id: message.message_type_id,
      message_stream_id: message.stream_id
    }

    header = if force_uncompressed == true, do: header, else: compress_header(state, header)

    {
      %{state | sent_headers: Map.put(state.sent_headers, csid, header)},
      serialize_to_bytes(header, message.payload)
    }
  end
  
  defp compress_header(state, header_to_send) do
    case Map.fetch(state.sent_headers, header_to_send.csid) do
      :error -> header_to_send

      {:ok, previous_header} ->
        current_delta = header_to_send.timestamp - previous_header.timestamp # TODO: get rtmp timestamp difference

        cond do
          header_to_send.message_stream_id != previous_header.message_stream_id -> header_to_send
          header_to_send.message_type_id != previous_header.message_type_id -> %{header_to_send | type: 1, last_timestamp_delta: current_delta}
          header_to_send.message_length != previous_header.message_length -> %{header_to_send | type: 1, last_timestamp_delta: current_delta}
          current_delta != previous_header.last_timestamp_delta -> %{header_to_send | type: 2, last_timestamp_delta: current_delta}
          true -> %{header_to_send | type: 3, last_timestamp_delta: current_delta}
        end      
    end
  end

  defp serialize_to_bytes(header = %Header{type: 0}, payload), do: serialize_type_0_header(header, payload)
  defp serialize_to_bytes(header = %Header{type: 1}, payload), do: serialize_type_1_header(header, payload)
  defp serialize_to_bytes(header = %Header{type: 2}, payload), do: serialize_type_2_header(header, payload)
  defp serialize_to_bytes(header = %Header{type: 3}, payload), do: serialize_type_3_header(header, payload)

  defp serialize_type_0_header(header, payload) do
    <<header.type::2, get_csid_binary(header.csid)::bitstring>> <>
      <<
        header.timestamp::3 * 8, # TODO: handle extended timestamp
        header.message_length::3 * 8,
        header.message_type_id::1 * 8,
        header.message_stream_id::size(4)-unit(8)-little
      >> <>
      payload
  end
  
  defp serialize_type_1_header(header, payload) do
    <<header.type::2, get_csid_binary(header.csid)::bitstring>> <>
      <<
        header.last_timestamp_delta::3 * 8, # TODO: handle extended timestamp delta
        header.message_length::3 * 8,
        header.message_type_id::1 * 8
      >> <>
      payload
  end 

  defp serialize_type_2_header(header, payload) do
    <<header.type::2, get_csid_binary(header.csid)::bitstring>><>
      <<header.last_timestamp_delta::3 * 8>> <> # TODO: handle extended timestamp delta
      payload
  end 

  defp serialize_type_3_header(header, payload) do
    <<header.type::2, get_csid_binary(header.csid)::bitstring>> <> payload
  end

  defp get_csid_binary(csid) when csid < 64, do: <<csid::6>>
  defp get_csid_binary(csid) when csid < 319, do: <<0::6, csid - 64::8>>
  defp get_csid_binary(csid) when csid < 65599, do: <<1::6, csid - 64::15>>

  defp split_message_to_chunk_size(state = %State{}, message, accumulator, total_payload_size) do
    if byte_size(message.payload) > state.sending_max_chunk_size do

      # Can't directly use struct property inside of binary pattern matching
      chunk_size = state.sending_max_chunk_size 

      <<chunk_payload::size(chunk_size)-binary, rest::binary>> = message.payload
      chunk_message = %{message | payload: chunk_payload}
      remaining_message = %{message | payload: rest}
      accumulator = [chunk_message | accumulator]
      total_payload_size = total_payload_size + byte_size(chunk_message.payload)

      split_message_to_chunk_size(state, remaining_message, accumulator, total_payload_size)
    else
      {total_payload_size + byte_size(message.payload), Enum.reverse([message | accumulator])}
    end
  end

end