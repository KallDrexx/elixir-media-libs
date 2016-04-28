defmodule RtmpCommon.Chunking.DataReaderTest do
  use ExUnit.Case, async: true
  
  setup do
    expected_binary = create_repeated_binary(55, 100)
    transport = BinaryTransportMock
    {:ok, socket} = transport.start_link(expected_binary)
    {:ok, transport: transport, expected_binary: expected_binary, socket: socket}
  end
  
  test "Type 0 chunk reads data specified in current header", %{transport: transport, expected_binary: expected_binary, socket: socket} do      
    header = %RtmpCommon.Chunking.ChunkHeader{type: 0, message_length: String.length(expected_binary)}
    
    {:ok, ^expected_binary} = RtmpCommon.Chunking.DataReader.read(nil, header, socket, transport)
  end
  
  test "Type 1 chunk reads data specified in current header", %{transport: transport, expected_binary: expected_binary, socket: socket} do
    header = %RtmpCommon.Chunking.ChunkHeader{type: 1, message_length: String.length(expected_binary)}
    
    {:ok, ^expected_binary} = RtmpCommon.Chunking.DataReader.read(nil, header, socket, transport)
  end
  
  test "Type 2 chunk reads data specified in previous header", %{transport: transport, expected_binary: expected_binary, socket: socket} do
    previous_header = %RtmpCommon.Chunking.ChunkHeader{type: 1, stream_id: 1234, message_length: String.length(expected_binary)}
    current_header = %RtmpCommon.Chunking.ChunkHeader{type: 2, stream_id: 1234, message_length: String.length(expected_binary)}
    
    {:ok, ^expected_binary} = RtmpCommon.Chunking.DataReader.read(previous_header, current_header, socket, transport)
  end
  
  test "Type 3 chunk reads data specified in previous header", %{transport: transport, expected_binary: expected_binary, socket: socket} do
    previous_header = %RtmpCommon.Chunking.ChunkHeader{type: 1, stream_id: 1234, message_length: String.length(expected_binary)}
    current_header = %RtmpCommon.Chunking.ChunkHeader{type: 3, stream_id: 1234, message_length: String.length(expected_binary)}
    
    {:ok, ^expected_binary} = RtmpCommon.Chunking.DataReader.read(previous_header, current_header, socket, transport)
  end
  
  test "Function clause error when stream_ids don't match", %{transport: transport, expected_binary: expected_binary, socket: socket} do
    previous_header = %RtmpCommon.Chunking.ChunkHeader{type: 1, stream_id: 1234, message_length: String.length(expected_binary)}
    current_header = %RtmpCommon.Chunking.ChunkHeader{type: 3, stream_id: 1235, message_length: String.length(expected_binary)}
    
    assert catch_error(RtmpCommon.Chunking.DataReader.read(previous_header, current_header, socket, transport))
  end  
  
  defp create_repeated_binary(byte, count) do
    List.duplicate(byte, count)
    |> IO.iodata_to_binary
  end
end