defmodule RtmpSession.ChunkIo do
  @moduledoc """
  This module provider an API for processing the raw binary that makes up
  RTMP chunks (and unpacking the enclosed RTMP message within) and allows
  serializing RTMP messages into binary RTMP chunks  
  """

  alias RtmpSession.RtmpMessage, as: RtmpMessage

  defmodule State do
    defstruct receiving_max_chunk_size: 128,
              received_headers: %{},
              sent_headers: %{},
              parse_stage: :chunk_type,
              current_header: nil,
              unparsed_binary: <<>>,
              incomplete_message: nil
  end

  defmodule Header do
    defstruct type: nil, 
              csid: nil,
              timestamp: nil,
              last_timestamp_delta: nil,
              message_length: nil,
              message_type_id: nil,
              message_stream_id: nil
  end

  require Logger

  @spec new() :: %State{}
  def new() do
    %State{}
  end

  @spec set_receiving_max_chunk_size(%State{}, pos_integer()) :: %State{}
  def set_receiving_max_chunk_size(state = %State{}, size) do
    %{state | receiving_max_chunk_size: size}
  end

  @spec deserialize(%State{}, <<>>) :: {%State{}, :incomplete} | {%State{}, %RtmpMessage{}} 
  def deserialize(state = %State{}, binary) when is_binary(binary) do
    do_deserialize(%{state | unparsed_binary: state.unparsed_binary <> binary})
  end

  @spec serialize(%State{}, %RtmpMessage{}, non_neg_integer(), boolean()) :: {%State{}, iodata()}
  def serialize(state = %State{}, message = %RtmpMessage{}, csid, force_uncompressed \\ false) do
    header = %Header{
      type: 0,
      csid: csid,
      timestamp: message.timestamp, # TODO: convert to rtmp timestamp
      last_timestamp_delta: 0,
      message_length: byte_size(message.payload),
      message_type_id: message.message_type_id,
      message_stream_id: message.stream_id
    }

    header = if force_uncompressed == true, do: header, else: compress_header(state, header)

    {
      %{state | sent_headers: Map.put(state.sent_headers, csid, header)},
      serialize_to_bytes(header, message.payload)
    }
  end

  ## Deserialization functions

  defp do_deserialize(state = %State{parse_stage: :chunk_type}), do: deserialize_chunk_type(state)
  defp do_deserialize(state = %State{parse_stage: :csid}), do: deserialize_csid(state)
  defp do_deserialize(state = %State{parse_stage: :message_header}), do: deserialize_message_header(state)
  defp do_deserialize(state = %State{parse_stage: :extended_timestamp}), do: deserialize_extended_timestamp(state)
  defp do_deserialize(state = %State{parse_stage: :data}), do: deserialize_data(state)

  defp deserialize_chunk_type(state) do
    if byte_size(state.unparsed_binary) == 0 do
      form_incomplete_result(state)
    else
      <<type::2, rest_of_first_byte::6, rest::binary>> = state.unparsed_binary
      new_state = %{state |
        current_header: %Header{type: type},
        unparsed_binary: <<rest_of_first_byte::6, rest::binary>>,
        parse_stage: :csid
      }

      deserialize_csid(new_state)
    end
  end

  defp deserialize_csid(state) do
    case get_csid(state.unparsed_binary) do
      {:error, :not_enough_binary} ->
        form_incomplete_result(state)

      {:ok, id, remaining_binary} -> 
        new_state = %{state |
          current_header: %{state.current_header | csid: id},
          unparsed_binary: remaining_binary,
          parse_stage: :message_header
        }

        deserialize_message_header(new_state)
    end    
  end

  defp get_csid(<<0::6, id::8, rest::binary>>), do: {:ok, id + 64, rest}
  defp get_csid(<<1::6, id::16, rest::binary>>), do: {:ok, id + 64, rest}
  defp get_csid(<<id::6, rest::binary>>) when id != 0 and id != 1, do: {:ok, id, rest}
  defp get_csid(_binary), do: {:error, :not_enough_binary}

  defp deserialize_message_header(state = %State{current_header: %Header{type: 0}, unparsed_binary: <<_::11 * 8, _::binary>>}), do: deserialize_type_0_message_header(state)
  defp deserialize_message_header(state = %State{current_header: %Header{type: 1}, unparsed_binary: <<_::7 * 8, _::binary>>}), do: deserialize_type_1_message_header(state)
  defp deserialize_message_header(state = %State{current_header: %Header{type: 2}, unparsed_binary: <<_::3 * 8, _::binary>>}), do: deserialize_type_2_message_header(state)
  defp deserialize_message_header(state = %State{current_header: %Header{type: 3}}), do: deserialize_type_3_message_header(state)
  defp deserialize_message_header(state), do: form_incomplete_result(state)

  defp deserialize_type_0_message_header(state) do
    <<timestamp::3 * 8, length::3 * 8, type_id::1 * 8, stream_id::4 * 8, rest::binary>> = state.unparsed_binary
    updated_header = %{state.current_header |
      timestamp: timestamp,
      last_timestamp_delta: 0,
      message_length: length,
      message_type_id: type_id,
      message_stream_id: stream_id
    }

    new_state = %{state |
       parse_stage: :extended_timestamp,
       current_header: updated_header,
       unparsed_binary: rest
    }

    deserialize_extended_timestamp(new_state)
  end

  defp deserialize_type_1_message_header(state) do
    previous_header = get_previous_header!(state.received_headers, state.current_header.csid, state.current_header.type)
    <<delta::3 * 8, length::3 * 8, type_id::1 * 8, rest::binary>> = state.unparsed_binary

    updated_header = %{state.current_header |
      timestamp: previous_header.timestamp + delta,
      last_timestamp_delta: delta,
      message_length: length,
      message_type_id: type_id,
      message_stream_id: previous_header.message_stream_id
    }

    new_state = %{state |
      parse_stage: :extended_timestamp,
      current_header: updated_header,
      unparsed_binary: rest
    }

    deserialize_extended_timestamp(new_state)
  end

  defp deserialize_type_2_message_header(state) do
    previous_header = get_previous_header!(state.received_headers, state.current_header.csid, state.current_header.type)
    <<delta::3 * 8, rest::binary>> = state.unparsed_binary

    updated_header = %{state.current_header |
      timestamp: previous_header.timestamp + delta,
      last_timestamp_delta: delta,
      message_length: previous_header.message_length,
      message_type_id: previous_header.message_type_id,
      message_stream_id: previous_header.message_stream_id
    }

    new_state = %{state |
      parse_stage: :extended_timestamp,
      current_header: updated_header,
      unparsed_binary: rest
    }

    deserialize_extended_timestamp(new_state)
  end

  defp deserialize_type_3_message_header(state) do
    previous_header = get_previous_header!(state.received_headers, state.current_header.csid, state.current_header.type)

    updated_header = %{state.current_header |
      timestamp: previous_header.timestamp + previous_header.last_timestamp_delta,
      last_timestamp_delta: previous_header.last_timestamp_delta,
      message_length: previous_header.message_length,
      message_type_id: previous_header.message_type_id,
      message_stream_id: previous_header.message_stream_id
    }

    new_state = %{state |
      parse_stage: :extended_timestamp,
      current_header: updated_header,
    }

    deserialize_extended_timestamp(new_state)
  end

  defp deserialize_extended_timestamp(state) do
    cond do
      state.current_header.type == 3 ->
        %{state | parse_stage: :data} |> deserialize_data()

      state.current_header.type == 0 && state.current_header.timestamp < 16777215 ->
        %{state | parse_stage: :data} |> deserialize_data()
      
      state.current_header.type != 0 && state.current_header.last_timestamp_delta < 16777215 ->
         %{state | parse_stage: :data} |> deserialize_data()

      byte_size(state.unparsed_binary) < 4 ->
        form_incomplete_result(state)

      true ->
        <<extended_timestamp::4 * 8, rest::binary>> = state.unparsed_binary
        updated_header = adjust_header_for_extended_timestamp(state.current_header, extended_timestamp)

        new_state = %{state |
          parse_stage: :data,
          current_header: updated_header,
          unparsed_binary: rest
        }

        deserialize_data(new_state)
    end
  end

  defp adjust_header_for_extended_timestamp(header, extended_timestamp) do
    if header.type == 0 do
      %{header | timestamp: 16777215 + extended_timestamp}
    else
      %{header | 
        last_timestamp_delta: 16777215 + extended_timestamp,
        timestamp: header.timestamp + extended_timestamp
      }
    end
  end

  defp deserialize_data(state) do
    message = if state.incomplete_message != nil do
      state.incomplete_message
    else
      %RtmpSession.RtmpMessage{
        timestamp: state.current_header.timestamp,
        message_type_id: state.current_header.message_type_id
      }
    end

    payload_so_far = byte_size(message.payload)
    full_message_length = state.current_header.message_length
    length_remaining = full_message_length - payload_so_far
    chunk_payload_length = Enum.min([length_remaining, state.receiving_max_chunk_size])

    if byte_size(state.unparsed_binary) < chunk_payload_length do
      form_incomplete_result(state)
    else
      <<data::size(chunk_payload_length)-binary, rest::binary>> = state.unparsed_binary

      message = %{message | payload: message.payload <> data}
      if byte_size(message.payload) == state.current_header.message_length do
        new_state = %{state |
          parse_stage: :chunk_type,
          received_headers: Map.put(state.received_headers, state.current_header.csid, state.current_header),
          unparsed_binary: rest,
          incomplete_message: nil
        }

        form_complete_result(new_state, message)
      else
        new_state = %{state |
          parse_stage: :chunk_type,
          received_headers: Map.put(state.received_headers, state.current_header.csid, state.current_header),
          unparsed_binary: rest,
          incomplete_message: message
        }

        form_incomplete_result(new_state)
      end
    end
  end 

  defp get_previous_header!(previous_headers, csid, current_chunk_type) do
    case Map.fetch(previous_headers, csid) do
      {:ok, value} -> value
      :error -> raise "Received type #{current_chunk_type} chunk header for chunk stream id #{csid} without receiving a type 0 chunk first"
    end
  end

  defp form_incomplete_result(state), do: {state, :incomplete}
  defp form_complete_result(state, message), do: {state, message}

  ## Serialization Functions

  
  
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
        header.message_stream_id::4 * 8
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

end