defmodule RtmpCommon.Chunking.Deserializer do
  @moduledoc """
  
  Deserializes RTMP chunks from passed in binary.  This is setup
  to allow incomplete chunks to be passed in.  
  
  Rtmp chunks that have been parsed from the binary stream can be
  retrieved by calling `get_deserialized_chunks()`.
  
  One instance of the deserializer should be created for each data stream.
  
  """
  
  @log_chunk_binary true
  
  alias RtmpCommon.Chunking.ChunkHeader, as: ChunkHeader
  require Logger
  
  defmodule State do
    defstruct parse_stage: :chunk_type,
              previous_headers: %{},
              current_header: nil,
              header_format: nil,
              unparsed_binary: <<>>,
              completed_chunks: [],
              current_chunk_binary: <<>>,
              completed_chunk_count: 0,
              max_chunk_size: 128,
              data_in_progress: <<>>,
              process_status: :waiting_for_data
  end
  
  @doc "Creates a new deserializer instance"
  @spec new() :: %State{}
  def new() do
    %State{}
  end
  
  @doc "Returns the deserializer instance with all unretrieved completed chunks"
  @spec get_deserialized_chunks(%State{}) :: {%State{}, [{%RtmpCommon.Chunking.ChunkHeader{}, binary()}]}
  def get_deserialized_chunks(state = %State{}) do
    {%{state | completed_chunks: []}, Enum.reverse(state.completed_chunks)}
  end
  
  @doc "Updates the max chunk size"
  @spec set_max_chunk_size(%State{}, pos_integer()) :: %State{}
  def set_max_chunk_size(state = %State{}, size) when size > 0 do
    %{state | max_chunk_size: size}
  end
  
  @doc "Gets the current deserialization status"
  @spec get_status(%State{}) :: :waiting_for_data | :processing
  def get_status(%State{process_status: status}) do
    status
  end
  
  @doc "Processes the passed in binary"  
  @spec process(%State{}, binary()) :: %State{}
  def process(state = %State{parse_stage: :chunk_type}, new_binary) when is_binary(new_binary) do  
    unparsed_binary = state.unparsed_binary <> new_binary
    
    if byte_size(unparsed_binary) == 0 do
      %{state | unparsed_binary: unparsed_binary, process_status: :waiting_for_data}
    else
      <<type::2, first_byte_rest::6, rest::binary>> = unparsed_binary   
      current_header = %ChunkHeader{type: type}
      
      %{state | 
        parse_stage: :stream_id,
        current_header: current_header, 
        header_format: first_byte_rest, 
        unparsed_binary: rest,
        current_chunk_binary: <<type::2, first_byte_rest::6>>
      } |> process(<<>>)
    end
  end
  
  def process(state = %State{parse_stage: :stream_id}, new_binary) when is_binary(new_binary) do
    unparsed_binary = state.unparsed_binary <> new_binary
    
    case get_stream_id(state.header_format, unparsed_binary) do
      {:error, :not_enough_binary} -> %{state | unparsed_binary: unparsed_binary, process_status: :waiting_for_data}
      {:ok, id, remaining_binary, read_binary} -> 
        updated_header = %{state.current_header | stream_id: id}
        
        %{state | 
          parse_stage: :message_header, 
          current_header: updated_header, 
          unparsed_binary: remaining_binary,
          current_chunk_binary: state.current_chunk_binary <> read_binary
        } |> process(<<>>)
    end
  end
  
  def process(state = %State{parse_stage: :message_header, current_header: %ChunkHeader{type: 0}}, new_binary) when is_binary(new_binary) do
    unparsed_binary = state.unparsed_binary <> new_binary
    
    if byte_size(unparsed_binary) < 11 do
      %{state | unparsed_binary: unparsed_binary, process_status: :waiting_for_data}
    else
      <<timestamp::3 * 8, message_length::3 * 8, message_type_id::1 * 8, message_stream_id::4 * 8, rest::binary>> = unparsed_binary
      updated_header = %{state.current_header |
        timestamp: timestamp,
        last_timestamp_delta: 0,
        message_length: message_length,
        message_type_id: message_type_id,
        message_stream_id: message_stream_id 
      }
      
      %{state | 
        parse_stage: :extended_timestamp, 
        current_header: updated_header, 
        unparsed_binary: rest,
        current_chunk_binary: state.current_chunk_binary <> <<timestamp::3 * 8, message_length::3 * 8, message_type_id::1 * 8, message_stream_id::4 * 8>>
      } |> process(<<>>)
    end
  end
  
  def process(state = %State{parse_stage: :message_header, current_header: %ChunkHeader{type: 1}}, new_binary) when is_binary(new_binary) do
    unparsed_binary = state.unparsed_binary <> new_binary
    
    if byte_size(unparsed_binary) < 7 do
      %{state | unparsed_binary: unparsed_binary, process_status: :waiting_for_data}
    else
      %ChunkHeader{        
        timestamp: previous_timestamp,
        message_stream_id: previous_stream_id
      } = get_previous_header!(state.previous_headers, state.current_header.stream_id, state.current_header.type, state)
            
      <<delta::3 * 8, message_length::3 * 8, message_type_id::1 * 8, rest::binary>> = unparsed_binary
      
      updated_header = %{state.current_header |
        timestamp: previous_timestamp + delta,
        last_timestamp_delta: delta,
        message_length: message_length,
        message_type_id: message_type_id,
        message_stream_id: previous_stream_id
      }
      
      %{state | 
        parse_stage: :extended_timestamp, 
        current_header: updated_header, 
        unparsed_binary: rest,
        current_chunk_binary: state.current_chunk_binary <> <<delta::3 * 8, message_length::3 * 8, message_type_id::1 * 8>>
      } |> process(<<>>)      
    end    
  end
  
  def process(state = %State{parse_stage: :message_header, current_header: %ChunkHeader{type: 2}}, new_binary) when is_binary(new_binary) do
    unparsed_binary = state.unparsed_binary <> new_binary
    
    if byte_size(unparsed_binary) < 3 do
      %{state | unparsed_binary: unparsed_binary, process_status: :waiting_for_data}
    else
      %ChunkHeader{
        timestamp: previous_timestamp,
        message_stream_id: previous_stream_id,
        message_length: previous_message_length,
        message_type_id: previous_message_type_id,
      } = get_previous_header!(state.previous_headers, state.current_header.stream_id, state.current_header.type, state)
            
      <<delta::3 * 8, rest::binary>> = unparsed_binary
      updated_header = %{state.current_header |
        timestamp: previous_timestamp + delta,
        last_timestamp_delta: delta,
        message_length: previous_message_length,
        message_type_id: previous_message_type_id,
        message_stream_id: previous_stream_id
      }
      
      %{state | 
        parse_stage: :extended_timestamp, 
        current_header: updated_header, 
        unparsed_binary: rest,
        current_chunk_binary: state.current_chunk_binary <> <<delta::3 * 8>>
      } |> process(<<>>)      
    end    
  end
  
  def process(state = %State{parse_stage: :message_header, current_header: %ChunkHeader{type: 3}}, new_binary) when is_binary(new_binary) do
    unparsed_binary = state.unparsed_binary <> new_binary
    
    %ChunkHeader{
        timestamp: previous_timestamp,
        last_timestamp_delta: previous_delta,
        message_stream_id: previous_stream_id,
        message_length: previous_message_length,
        message_type_id: previous_message_type_id,
      } = get_previous_header!(state.previous_headers, state.current_header.stream_id, state.current_header.type, state)
            
      updated_header = %{state.current_header |
        timestamp: previous_timestamp + previous_delta,
        last_timestamp_delta: previous_delta,
        message_length: previous_message_length,
        message_type_id: previous_message_type_id,
        message_stream_id: previous_stream_id
      }
      
      %{state | 
        parse_stage: :data, 
        current_header: updated_header, 
        unparsed_binary: unparsed_binary
      } |> process(<<>>)  
  end
  
  def process(state = %State{parse_stage: :extended_timestamp, current_header: %ChunkHeader{type: 0}}, new_binary) when is_binary(new_binary) do
    unparsed_binary = state.unparsed_binary <> new_binary
    
    cond do
      state.current_header.timestamp < 16777215 -> 
        %{state | parse_stage: :data, unparsed_binary: unparsed_binary} |> process(<<>>)
          
      byte_size(unparsed_binary) < 4 -> 
        %{state | unparsed_binary: unparsed_binary}
        
      true -> 
        <<extended_timestamp::4 * 8, rest::binary>> = unparsed_binary
        updated_header = %{state.current_header | timestamp: 16777215 + extended_timestamp}
        
        %{state | 
          parse_stage: :data, 
          current_header: updated_header, 
          unparsed_binary: rest,
          current_chunk_binary: state.current_chunk_binary <> <<extended_timestamp::4 * 8>>
        } |> process(<<>>)  
    end
  end
  
  def process(state = %State{parse_stage: :extended_timestamp}, new_binary) when is_binary(new_binary) do
    unparsed_binary = state.unparsed_binary <> new_binary
    
    cond do
      state.current_header.last_timestamp_delta < 16777215 -> 
        %{state | parse_stage: :data, unparsed_binary: unparsed_binary} |> process(<<>>)
          
      byte_size(unparsed_binary) < 4 -> 
        %{state | unparsed_binary: unparsed_binary}
        
      true -> 
        <<extended_delta::4 * 8, rest::binary>> = unparsed_binary
        
        updated_header = %{state.current_header | 
          timestamp: state.current_header.timestamp + extended_delta,
          last_timestamp_delta: state.current_header.last_timestamp_delta + extended_delta
        }
        
        %{state | 
          parse_stage: :data, 
          current_header: updated_header, 
          unparsed_binary: rest,
          current_chunk_binary: state.current_chunk_binary <> <<extended_delta::4 * 8>>
        } |> process(<<>>)  
    end
  end
  
  def process(state = %State{parse_stage: :data}, new_binary) when is_binary(new_binary) do
    unparsed_binary = state.unparsed_binary <> new_binary
    
    # If the message length is greater than the max of a single chunk payload, 
    # we need to hold onto the data until we have a complete rtmp message
    payload_remaining = state.current_header.message_length - byte_size(state.data_in_progress)
    chunk_data_length = min(state.max_chunk_size, payload_remaining)
    
    if byte_size(unparsed_binary) < chunk_data_length do
      %{state | parse_stage: :data, unparsed_binary: unparsed_binary, process_status: :waiting_for_data}
    else
      <<data::size(chunk_data_length)-binary, rest::binary>> = unparsed_binary
            
      completed_chunk_binary = state.current_chunk_binary <> data
      log_chunk_binary(state.completed_chunk_count, completed_chunk_binary)      
      
      new_state = %{state | 
        parse_stage: :chunk_type, 
        unparsed_binary: rest,
        previous_headers: Map.put(state.previous_headers, state.current_header.stream_id, state.current_header),
        current_chunk_binary: <<>>,
        completed_chunk_count: state.completed_chunk_count + 1
      }
      
      if payload_remaining - chunk_data_length > 0 do
        # Message is not complete
        %{new_state | data_in_progress: data}  |> process(<<>>)
      else
        # Message is finished
        
        # NOTE: We can't recursively call process(<<>>) here to automatically process the next chunk
        #   because if we have a complete RTMP message we must handle that message prior to
        #   deserializing the next chunk.  Otherwise a SetChunkSize message might be received
        #   which will be needed in order to correctly deserialize the next RTMP message. 
        
        %{new_state |
          process_status: :processing,
          data_in_progress: <<>>,
          completed_chunks: [{state.current_header, state.data_in_progress <> data} | state.completed_chunks]
        }
      end 
    end
  end
  
  defp get_stream_id(0, binary) do
    if byte_size(binary) == 0 do
      {:error, :not_enough_binary}
    else
      <<id::8, rest::binary>> = binary
      {:ok, id + 64, rest, <<id::8>>}
    end
  end
  
  defp get_stream_id(1, binary) do
    if byte_size(binary) < 2 do
      {:error, :not_enough_binary}
    else
      <<id::16, rest::binary>> = binary
      {:ok, id + 64, rest, <<id::16>>}
    end
  end
  
  defp get_stream_id(x, binary) do
    {:ok, x, binary, <<>>}
  end
  
  defp get_previous_header!(previous_headers, stream_id, current_chunk_type, state) do
    case Map.fetch(previous_headers, stream_id) do
      {:ok, value} -> value
      :error ->
        log_chunk_binary(state.completed_chunk_count, state.current_chunk_binary)
        raise "Received type #{current_chunk_type} chunk header for chunk stream id #{stream_id} without receiving a type 0 chunk first"
    end
  end
  
  defp log_chunk_binary(completed_chunk_count, binary) do
    if @log_chunk_binary do        
      {{year, month, day}, {hour, minute, second}} = :calendar.local_time
      date = "#{year}#{String.rjust(Integer.to_string(month), 2, 48)}#{String.rjust(Integer.to_string(day), 2, 48)}"
      time = "#{String.rjust(Integer.to_string(hour), 2, 48)}#{String.rjust(Integer.to_string(minute), 2, 48)}#{String.rjust(Integer.to_string(second), 2, 48)}"
      
      chunk_number = 
        completed_chunk_count + 1
        |> Integer.to_string()
        |> String.rjust(4, 48)        
      
      directory = "C:/temp/rtmp_chunks/#{date}"
      :ok = File.mkdir_p(directory)
      
      {:ok, file} = File.open("#{directory}/#{time}-#{chunk_number}", [:write])
      IO.binwrite(file, binary)        
    end
  end
  
end