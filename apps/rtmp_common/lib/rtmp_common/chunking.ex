defmodule RtmpCommon.Chunking do
  
  @doc "reads the next RTMP chunk from the socket"
  def read_next_chunk(socket, transport, previous_headers) do
    with {:ok, current_header} <- read_header(socket, transport),
            previous_header = Map.get(previous_headers, current_header.stream_id),
            {:ok, data} <- read_data(previous_header, current_header, socket, transport),
            filled_in_header = fill_previous_header(previous_header, current_header),
            updated_header_map = Map.put(previous_headers, current_header.stream_id, filled_in_header),
            do: {:ok, {updated_header_map, filled_in_header, data}}
  end
  
  defp read_header(socket, transport) do
    with {:ok, {type_id, rest_of_first_byte}} <- get_chunk_type(socket, transport),
          {:ok, stream_id} <- get_stream_id(rest_of_first_byte, socket, transport),
          {:ok, chunk = %RtmpCommon.Chunking.ChunkHeader{}} <- parse_header(type_id, socket, transport),
          do: {:ok, %{chunk | type: type_id, stream_id: stream_id}}
  end
  
  defp read_data(previous_chunk_header, current_chunk_header, socket, transport) do
    do_read_data(previous_chunk_header, current_chunk_header, socket, transport)
  end 
  
  # Since some headers are missing information, we want to fill the previous header 
  # with as much information as possible, so we can have that data
  # for the next chunk that may come down without that info
  defp fill_previous_header(nil, current_header) do
    current_header
  end
  
  defp fill_previous_header(_, current_header = %RtmpCommon.Chunking.ChunkHeader{type: 0}) do
    current_header
  end
    
  defp fill_previous_header(previous_header, current_header = %RtmpCommon.Chunking.ChunkHeader{type: 1}) do
    %{current_header | message_stream_id: previous_header.message_stream_id}
  end
    
  defp fill_previous_header(previous_header, current_header = %RtmpCommon.Chunking.ChunkHeader{type: 2}) do
    %{current_header | 
      message_stream_id: previous_header.message_stream_id,
      message_type_id: previous_header.message_type_id,
      message_length: previous_header.message_length    
    }
  end
    
  defp fill_previous_header(previous_header, current_header = %RtmpCommon.Chunking.ChunkHeader{type: 3}) do
    %{current_header | 
      message_stream_id: previous_header.message_stream_id,
      message_type_id: previous_header.message_type_id,
      message_length: previous_header.message_length,
      timestamp: previous_header.timestamp    
    }
  end
  
  defp get_chunk_type(socket, transport) do
    case transport.recv(socket, 1, 5000) do
      {:ok, <<type_id::2, rest::6>>} -> {:ok, {type_id, rest}}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp get_stream_id(0, socket, transport) do
    case transport.recv(socket, 1, 5000) do
      {:ok, <<id::8>>} -> {:ok, id + 64}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp get_stream_id(1, socket, transport) do
    case transport.recv(socket, 2, 5000) do
      {:ok, <<id::16>>} -> {:ok, id + 64}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp get_stream_id(byte_1_rest_value, _socket, _transport) do
    {:ok, byte_1_rest_value}
  end
  
  # Parses chunk type 0 headers
  defp parse_header(0, socket, transport) do
    result = with {:ok, <<timestamp::size(3)-unit(8)>>} <- transport.recv(socket, 3, 5000),
                    {:ok, <<message_length::size(3)-unit(8)>>} <- transport.recv(socket, 3, 5000),
                    {:ok, <<message_type_id::8>>} <- transport.recv(socket, 1, 5000),
                    {:ok, <<message_stream_id::size(4)-unit(8)>>} <- transport.recv(socket, 4, 5000),
                    {:ok, final_timestamp} <- parse_extended_timestamp(timestamp, socket, transport),
                    do: {:ok, %RtmpCommon.Chunking.ChunkHeader{timestamp: final_timestamp,
                                                          message_length: message_length,
                                                          message_type_id: message_type_id,
                                                          message_stream_id: message_stream_id}}
          
    case result do
      {:ok, chunk = %RtmpCommon.Chunking.ChunkHeader{}} -> {:ok, chunk}
      {:error, reason} -> {:error, reason}
    end
  end
  
  # Parses chunk type 1 headers
  defp parse_header(1, socket, transport) do
    result = with {:ok, <<timestamp::size(3)-unit(8)>>} <- transport.recv(socket, 3, 5000),
                    {:ok, <<message_length::size(3)-unit(8)>>} <- transport.recv(socket, 3, 5000),
                    {:ok, <<message_type_id::8>>} <- transport.recv(socket, 1, 5000),
                    {:ok, final_timestamp} <- parse_extended_timestamp(timestamp, socket, transport),
                    do: {:ok, %RtmpCommon.Chunking.ChunkHeader{timestamp: final_timestamp,
                                                          message_length: message_length,
                                                          message_type_id: message_type_id}}
          
    case result do
      {:ok, chunk = %RtmpCommon.Chunking.ChunkHeader{}} -> {:ok, chunk}
      {:error, reason} -> {:error, reason}
    end
  end
  
  # Parses chunk type 2 headers
  defp parse_header(2, socket, transport) do
    result = with {:ok, <<timestamp::size(3)-unit(8)>>} <- transport.recv(socket, 3, 5000),
                    {:ok, final_timestamp} <- parse_extended_timestamp(timestamp, socket, transport),
                    do: {:ok, %RtmpCommon.Chunking.ChunkHeader{timestamp: final_timestamp}}
          
    case result do
      {:ok, chunk = %RtmpCommon.Chunking.ChunkHeader{}} -> {:ok, chunk}
      {:error, reason} -> {:error, reason}
    end
  end
  
  # Parses chunk type 3 headers
  defp parse_header(3, _socket, _transport) do
    {:ok, %RtmpCommon.Chunking.ChunkHeader{}}
  end
  
  defp parse_extended_timestamp(original_timestamp, _, _) when original_timestamp < 16777215, do: {:ok, original_timestamp}
  defp parse_extended_timestamp(original_timestamp, socket, transport) do
    case transport.recv(socket, 4, 5000) do
      {:ok, <<extended_timestamp::size(4)-unit(8)>>} -> {:ok, original_timestamp + extended_timestamp}
      {:error, reason} -> {:error, reason}
    end
  end
  
  def do_read_data(_, %RtmpCommon.Chunking.ChunkHeader{type: 0, message_length: length}, socket, transport) do
    case transport.recv(socket, length, 5000) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, reason}
    end
  end
  
  def do_read_data(_, %RtmpCommon.Chunking.ChunkHeader{type: 1, message_length: length}, socket, transport) do
    case transport.recv(socket, length, 5000) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, reason}
    end
  end  
  
  def do_read_data(%RtmpCommon.Chunking.ChunkHeader{message_length: length, stream_id: stream_id}, 
              %RtmpCommon.Chunking.ChunkHeader{type: 2, stream_id: stream_id}, socket, transport) do
    case transport.recv(socket, length, 5000) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, reason}
    end
  end  
  
  def do_read_data(%RtmpCommon.Chunking.ChunkHeader{message_length: length, stream_id: stream_id}, 
              %RtmpCommon.Chunking.ChunkHeader{type: 3, stream_id: stream_id}, socket, transport) do
    case transport.recv(socket, length, 5000) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, reason}
    end
  end
  
  def do_read_data(nil, _, socket, transport) do
    {:error, :no_previous_chunk}
  end
end