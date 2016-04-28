defmodule RtmpCommon.Chunking.DataReader do
  def read(previous_chunk_header, current_chunk_header, socket, transport) do
    do_read(previous_chunk_header, current_chunk_header, socket, transport)
  end
  
  def do_read(_, %RtmpCommon.Chunking.ChunkHeader{type: 0, message_length: length}, socket, transport) do
    case transport.recv(socket, length, 5000) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, reason}
    end
  end
  
  def do_read(_, %RtmpCommon.Chunking.ChunkHeader{type: 1, message_length: length}, socket, transport) do
    case transport.recv(socket, length, 5000) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, reason}
    end
  end  
  
  def do_read(%RtmpCommon.Chunking.ChunkHeader{message_length: length, stream_id: stream_id}, 
              %RtmpCommon.Chunking.ChunkHeader{type: 2, stream_id: stream_id}, socket, transport) do
    case transport.recv(socket, length, 5000) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, reason}
    end
  end  
  
  def do_read(%RtmpCommon.Chunking.ChunkHeader{message_length: length, stream_id: stream_id}, 
              %RtmpCommon.Chunking.ChunkHeader{type: 3, stream_id: stream_id}, socket, transport) do
    case transport.recv(socket, length, 5000) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, reason}
    end
  end
end