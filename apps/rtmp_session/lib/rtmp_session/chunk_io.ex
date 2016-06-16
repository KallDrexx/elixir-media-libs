defmodule RtmpSession.ChunkIo do
  @moduledoc """
  This module provider an API for processing the raw binary that makes up
  RTMP chunks (and unpacking the enclosed RTMP message within) and allows
  serializing RTMP messages into binary RTMP chunks  
  """

  defmodule State do
    defstruct peer_max_chunk_size: 128,
              received_headers: %{},
              parse_stage: :chunk_type,
              current_header: nil,
              unparsed_binary: <<>>
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

  @spec deserialize(%State{}, <<>>) :: {%State{}, :incomplete} | {%State{}, %RtmpSession.Messages.RtmpMessage{}} 
  def deserialize(state = %State{}, binary) when is_binary(binary) do
    do_deserialize(%{state | unparsed_binary: state.unparsed_binary <> binary})
  end

  @spec serialize(%State{}, %RtmpSession.Messages.RtmpMessage{}) :: {%State{}, <<>>}
  def serialize(_state = %State{}, _message = %RtmpSession.Messages.RtmpMessage{}) do
    raise("not implemented")
  end

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
    # TODO: Update to handle messages greater than peer_max_chunk_size
    chunk_length = state.current_header.message_length

    if byte_size(state.unparsed_binary) < chunk_length do
      form_incomplete_result(state)
    else
      <<data::size(chunk_length)-binary, rest::binary>> = state.unparsed_binary

      message = %RtmpSession.Messages.RtmpMessage{
        timestamp: state.current_header.timestamp,
        message_type_id: state.current_header.message_type_id,
        payload: data
      }

      new_state = %{state |
        parse_stage: :chunk_type,
        received_headers: Map.put(state.received_headers, state.current_header.csid, state.current_header),
        unparsed_binary: rest
      }

      form_complete_result(new_state, message)
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
end