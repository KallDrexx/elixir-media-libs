defmodule RtmpCommon.Chunking.Deserializer do
  alias RtmpCommon.Chunking.ChunkHeader, as: ChunkHeader
  require Logger
  
  @moduledoc """
  
  Deserializes RTMP chunks from passed in binary.  This is setup
  to allow incomplete chunks to be passed in.  
  
  Upon receiving enough binary to form a complete RTMP chunk the desired 
  MFA is called to distribute the deserialized RTMP chunk for further processing.
  
  The MFA is called with the passed in arguments first, then the chunk header, 
  and then then the binary data representing the chunk's data.
  
  One instance of the deserializer should be created for each data stream.
  
  """
  
  defmodule State do
    defstruct parse_stage: :chunk_type,
              completed_chunk_mfa: nil,
              previous_headers: %{},
              current_header: nil,
              header_format: nil,
              unparsed_binary: <<>>
  end
  
  @doc "Creates a new deserializer instance"
  def new({module, fun, args}) when is_atom(module) and is_atom(fun) and is_list(args)  do
    %State{completed_chunk_mfa: {module, fun, args}}
  end
  
  @doc "Processes the passed in binary"  
  def process(state = %State{parse_stage: :chunk_type}, new_binary) when is_binary(new_binary) do
    Logger.debug "Processing chunk_type stage"
    
    unparsed_binary = state.unparsed_binary <> new_binary
    
    if byte_size(unparsed_binary) == 0 do
      %{state | unparsed_binary: unparsed_binary}
    else
      <<type::2, first_byte_rest::6, rest::binary>> = unparsed_binary
      
      Logger.debug "chunk type: #{type}"
    
      current_header = %ChunkHeader{type: type}
      
      %{state | 
        parse_stage: :stream_id,
        current_header: current_header, 
        header_format: first_byte_rest, 
        unparsed_binary: rest
      } |> process(<<>>)
    end
  end
  
  def process(state = %State{parse_stage: :stream_id}, new_binary) when is_binary(new_binary) do
    Logger.debug "Processing stream_id stage"
    
    unparsed_binary = state.unparsed_binary <> new_binary
    
    case get_stream_id(state.header_format, unparsed_binary) do
      {:error, :not_enough_binary} -> %{state | unparsed_binary: unparsed_binary}
      {:ok, id, remaining_binary} -> 
        updated_header = %{state.current_header | stream_id: id}
        
        %{state | parse_stage: :message_header, current_header: updated_header, unparsed_binary: remaining_binary}
        |> process(<<>>)
    end
  end
  
  def process(state = %State{parse_stage: :message_header, current_header: %ChunkHeader{type: 0}}, new_binary) when is_binary(new_binary) do
    Logger.debug "Processing message_header stage"
    
    unparsed_binary = state.unparsed_binary <> new_binary
    
    if byte_size(unparsed_binary) < 11 do
      %{state | unparsed_binary: unparsed_binary}
    else
      <<timestamp::3 * 8, message_length::3 * 8, message_type_id::1 * 8, message_stream_id::4 * 8, rest::binary>> = unparsed_binary
      updated_header = %{state.current_header |
        timestamp: timestamp,
        last_timestamp_delta: 0,
        message_length: message_length,
        message_type_id: message_type_id,
        message_stream_id: message_stream_id 
      }
      
      %{state | parse_stage: :extended_timestamp, current_header: updated_header, unparsed_binary: rest}
      |> process(<<>>)
    end
  end
  
  def process(state = %State{parse_stage: :message_header, current_header: %ChunkHeader{type: 1}}, new_binary) when is_binary(new_binary) do
    Logger.debug "Processing message_header stage"
    
    unparsed_binary = state.unparsed_binary <> new_binary
    
    if byte_size(unparsed_binary) < 7 do
      %{state | unparsed_binary: unparsed_binary}
    else
      %ChunkHeader{        
        timestamp: previous_timestamp,
        message_stream_id: previous_stream_id
      } = get_previous_header!(state.previous_headers, state.current_header.stream_id)
            
      <<delta::3 * 8, message_length::3 * 8, message_type_id::1 * 8, rest::binary>> = unparsed_binary
      Logger.debug "Delta: #{delta}"
      Logger.debug "Previous timestamp: #{previous_timestamp}"
      
      updated_header = %{state.current_header |
        timestamp: previous_timestamp + delta,
        last_timestamp_delta: delta,
        message_length: message_length,
        message_type_id: message_type_id,
        message_stream_id: previous_stream_id
      }
      
      %{state | parse_stage: :extended_timestamp, current_header: updated_header, unparsed_binary: rest}
      |> process(<<>>)      
    end    
  end
  
  def process(state = %State{parse_stage: :message_header, current_header: %ChunkHeader{type: 2}}, new_binary) when is_binary(new_binary) do
    Logger.debug "Processing message_header stage"
    
    unparsed_binary = state.unparsed_binary <> new_binary
    
    if byte_size(unparsed_binary) < 3 do
      %{state | unparsed_binary: unparsed_binary}
    else
      %ChunkHeader{
        timestamp: previous_timestamp,
        message_stream_id: previous_stream_id,
        message_length: previous_message_length,
        message_type_id: previous_message_type_id,
      } = get_previous_header!(state.previous_headers, state.current_header.stream_id)
            
      <<delta::3 * 8, rest::binary>> = unparsed_binary
      updated_header = %{state.current_header |
        timestamp: previous_timestamp + delta,
        last_timestamp_delta: delta,
        message_length: previous_message_length,
        message_type_id: previous_message_type_id,
        message_stream_id: previous_stream_id
      }
      
      %{state | parse_stage: :extended_timestamp, current_header: updated_header, unparsed_binary: rest}
      |> process(<<>>)      
    end    
  end
  
  def process(state = %State{parse_stage: :message_header, current_header: %ChunkHeader{type: 3}}, new_binary) when is_binary(new_binary) do
    Logger.debug "Processing message_header stage"
    
    unparsed_binary = state.unparsed_binary <> new_binary
    
    %ChunkHeader{
        timestamp: previous_timestamp,
        last_timestamp_delta: previous_delta,
        message_stream_id: previous_stream_id,
        message_length: previous_message_length,
        message_type_id: previous_message_type_id,
      } = get_previous_header!(state.previous_headers, state.current_header.stream_id)
            
      updated_header = %{state.current_header |
        timestamp: previous_timestamp + previous_delta,
        last_timestamp_delta: previous_delta,
        message_length: previous_message_length,
        message_type_id: previous_message_type_id,
        message_stream_id: previous_stream_id
      }
      
      %{state | parse_stage: :data, current_header: updated_header, unparsed_binary: unparsed_binary}
      |> process(<<>>)  
  end
  
  def process(state = %State{parse_stage: :extended_timestamp, current_header: %ChunkHeader{type: 0}}, new_binary) when is_binary(new_binary) do
    Logger.debug "Processing extended_timestamp stage"
    
    unparsed_binary = state.unparsed_binary <> new_binary
    
    cond do
      state.current_header.timestamp < 16777215 -> %{state | parse_stage: :data, unparsed_binary: unparsed_binary} |> process(<<>>)  
      byte_size(unparsed_binary) < 4 -> %{state | unparsed_binary: unparsed_binary}
      true -> 
        <<extended_timestamp::4 * 8, rest::binary>> = unparsed_binary
        updated_header = %{state.current_header | timestamp: 16777215 + extended_timestamp}
        
        %{state | parse_stage: :data, current_header: updated_header, unparsed_binary: rest}
        |> process(<<>>)  
    end
  end
  
  def process(state = %State{parse_stage: :extended_timestamp}, new_binary) when is_binary(new_binary) do
    Logger.debug "Processing extended_timestamp stage"
    
    unparsed_binary = state.unparsed_binary <> new_binary
    
    cond do
      state.current_header.last_timestamp_delta < 16777215 -> %{state | parse_stage: :data, unparsed_binary: unparsed_binary} |> process(<<>>)  
      byte_size(unparsed_binary) < 4 -> %{state | unparsed_binary: unparsed_binary}
      true -> 
        <<extended_delta::4 * 8, rest::binary>> = unparsed_binary
        
        updated_header = %{state.current_header | 
          timestamp: state.current_header.timestamp + extended_delta,
          last_timestamp_delta: state.current_header.last_timestamp_delta + extended_delta
        }
        
        %{state | parse_stage: :data, current_header: updated_header, unparsed_binary: rest}
        |> process(<<>>)  
    end
  end
  
  def process(state = %State{parse_stage: :data}, new_binary) when is_binary(new_binary) do
    Logger.debug "Processing data stage"
    
    unparsed_binary = state.unparsed_binary <> new_binary
    
    if byte_size(unparsed_binary) < state.current_header.message_length do
      %{state | parse_stage: :data, unparsed_binary: unparsed_binary}
    else
      length = state.current_header.message_length
      <<data::size(length)-unit(8), rest::binary>> = unparsed_binary
      
      {module, function, arguments} = state.completed_chunk_mfa
      apply(module, function, arguments ++ [state.current_header, <<data::size(length)-unit(8)>>])
      
      %{state | 
        parse_stage: :chunk_type, 
        unparsed_binary: rest,
        previous_headers: Map.put(state.previous_headers, state.current_header.stream_id, state.current_header)
      }
      |> process(<<>>)
    end
  end
  
  defp get_stream_id(0, binary) do
    if byte_size(binary) == 0 do
      {:error, :not_enough_binary}
    else
      <<id::8, rest::binary>> = binary
      {:ok, id + 64, rest}
    end
  end
  
  defp get_stream_id(1, binary) do
    if byte_size(binary) < 2 do
      {:error, :not_enough_binary}
    else
      <<id::16, rest::binary>> = binary
      {:ok, id + 64, rest}
    end
  end
  
  defp get_stream_id(x, binary) do
    {:ok, x, binary}
  end
  
  defp get_previous_header!(previous_headers, stream_id) do
    case Map.fetch(previous_headers, stream_id) do
      {:ok, value} -> value
      :error -> raise "Received non-type 0 chunk header for chunk stream id #{stream_id} without receiving a type 0 chunk first"
    end
  end
  
end