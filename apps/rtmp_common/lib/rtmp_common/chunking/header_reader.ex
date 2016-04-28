defmodule RtmpCommon.Chunking.HeaderReader do
  
  @doc "Reads the next rtmp chunk from the socket"
  def read(socket, transport) do
    with {:ok, {type_id, rest_of_first_byte}} <- get_chunk_type(socket, transport),
          {:ok, stream_id} <- get_stream_id(rest_of_first_byte, socket, transport),
          {:ok, chunk = %RtmpCommon.Chunking.ChunkHeader{}} <- parse_header(type_id, socket, transport),
          do: {:ok, %{chunk | type: type_id, stream_id: stream_id}}
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
                    do: {:ok, %RtmpCommon.Chunking.ChunkHeader{timestamp: timestamp,
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
                    do: {:ok, %RtmpCommon.Chunking.ChunkHeader{timestamp: timestamp,
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
                    do: {:ok, %RtmpCommon.Chunking.ChunkHeader{timestamp: timestamp}}
          
    case result do
      {:ok, chunk = %RtmpCommon.Chunking.ChunkHeader{}} -> {:ok, chunk}
      {:error, reason} -> {:error, reason}
    end
  end
  
  # Parses chunk type 3 headers
  defp parse_header(3, _socket, _transport) do
    {:ok, %RtmpCommon.Chunking.ChunkHeader{}}
  end
end