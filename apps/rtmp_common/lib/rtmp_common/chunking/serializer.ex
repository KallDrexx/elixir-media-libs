defmodule RtmpCommon.Chunking.Serializer do
  @moduledoc """  
  Serializes RTMP messages into bytes representing RTMP chunks.
  """
  
  alias RtmpCommon.Chunking.ChunkHeader, as: ChunkHeader
  alias RtmpCommon.RtmpTime, as: RtmpTime
  
  defmodule State do
    defstruct previously_serialized_chunks: %{}
  end
  
  def new() do
    %State{}
  end
  
  def serialize(state = %State{}, 
                rtmp_timestamp, 
                chunk_stream_id, 
                message = %{__struct__: struct_type}, 
                message_stream_id,
                force_uncompressed \\ false) 
  do
    {:ok, serialized_message} = struct_type.serialize(message)
    previous_header = Map.get(state.previously_serialized_chunks, chunk_stream_id)
    
    {current_header, chunk_binary} = 
      do_serialize(previous_header, rtmp_timestamp, chunk_stream_id, serialized_message, message_stream_id, force_uncompressed)
      
    updated_headers = Map.put(state.previously_serialized_chunks, chunk_stream_id, current_header)
    new_state = %State{state | previously_serialized_chunks: updated_headers}
    
    {new_state, chunk_binary}
  end
  
  defp do_serialize(previous_header, 
                    timestamp, 
                    chunk_stream_id, 
                    serialized_message, 
                    message_stream_id,
                    force_uncompressed) 
  do
    header = 
      create_header(timestamp, chunk_stream_id, serialized_message, message_stream_id) 
      |> update_header(previous_header, force_uncompressed)
      
      
    result = header_to_binary(header) <> serialized_message.data
    
    {header, result}
  end
  
  defp create_header(timestamp, chunk_stream_id, serialized_message, message_stream_id) do
    header = %ChunkHeader{
      type: 0,
      stream_id: chunk_stream_id,
      timestamp: timestamp,
      message_type_id: serialized_message.message_type_id,
      message_stream_id: message_stream_id,
      message_length: byte_size(serialized_message.data)
    }
    
    header
  end
  
  defp update_header(current_header, _, true) do
    current_header
  end
  
  defp update_header(current_header, nil, false) do
    current_header
  end
  
  defp update_header(current_header, previous_header, false) do
    delta = RtmpTime.get_delta(previous_header.timestamp, current_header.timestamp)
    
    cond do
      previous_header.message_stream_id != current_header.message_stream_id -> 
        current_header
        
      previous_header.message_type_id != current_header.message_type_id ||
      previous_header.message_length != current_header.message_length -> 
        %{previous_header |
          type: 1,
          timestamp: current_header.timestamp,
          last_timestamp_delta: delta,
          message_length: current_header.message_length,
          message_type_id: current_header.message_type_id 
        }
                
      previous_header.last_timestamp_delta != delta ->
        %{previous_header |
          type: 2,
          timestamp: current_header.timestamp,
          last_timestamp_delta: delta
        }
      
      true ->
        %{previous_header |
          type: 3,
          timestamp: current_header.timestamp
        }
    end
  end
  
  defp header_to_binary(header = %ChunkHeader{type: 0, stream_id: csid}) when csid < 64 do
    <<0::2, 
      csid::6, 
      header.timestamp::3 * 8,
      header.message_length::3 * 8, 
      header.message_type_id::1 * 8,
      header.message_stream_id::4 * 8
    >>
  end
  
  defp header_to_binary(header = %ChunkHeader{type: 1, stream_id: csid}) when csid < 64 do
    <<1::2, 
      csid::6, 
      header.last_timestamp_delta::3 * 8,
      header.message_length::3 * 8, 
      header.message_type_id::1 * 8
    >>
  end
  
  defp header_to_binary(header = %ChunkHeader{type: 2, stream_id: csid}) when csid < 64 do
    <<2::2, 
      csid::6, 
      header.last_timestamp_delta::3 * 8
    >>
  end
  
  defp header_to_binary(%ChunkHeader{type: 3, stream_id: csid}) when csid < 64 do
    <<3::2, csid::6>>
  end
end