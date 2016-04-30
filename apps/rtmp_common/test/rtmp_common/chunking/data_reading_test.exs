defmodule RtmpCommon.Chunking.DataReadingTest do
  use ExUnit.Case, async: true
  
  setup do
    transport = BinaryTransportMock
    binary_data = create_repeated_binary(55, 100)
    {:ok, transport: transport, binary_data: binary_data}
  end
  
  test "Type 0 chunk reads data specified in current header", %{transport: transport, binary_data: binary_data} do
    {:ok, socket} = __MODULE__.Mock.start_type_0_chunk(binary_data)
    {:ok, {_, _, ^binary_data}} = RtmpCommon.Chunking.read_next_chunk(socket, transport, %{})
  end
  
  test "Type 1 chunk reads data specified in current header", %{transport: transport, binary_data: binary_data} do
    {:ok, socket} = __MODULE__.Mock.start_type_0_chunk(binary_data)
    {:ok, {_, _, ^binary_data}} = RtmpCommon.Chunking.read_next_chunk(socket, transport, %{})
  end
  
  test "Type 2 chunk reads data specified in previous header", %{transport: transport, binary_data: binary_data} do
    previous_header = %RtmpCommon.Chunking.ChunkHeader{type: 2, 
                                      stream_id: 50,
                                      timestamp: 72,
                                      message_length: byte_size(binary_data),
                                      message_type_id: 3,
                                      message_stream_id: 55}
    
    
    previous_headers = Map.put(%{}, 50, previous_header)    
    {:ok, socket} = __MODULE__.Mock.start_type_2_chunk(binary_data)
                                          
    {:ok, {_, _, ^binary_data}} = RtmpCommon.Chunking.read_next_chunk(socket, transport, previous_headers)
  end
  
  test "Type 3 chunk reads data specified in previous header", %{transport: transport, binary_data: binary_data} do
    previous_header = %RtmpCommon.Chunking.ChunkHeader{type: 1, 
                                      stream_id: 50,
                                      timestamp: 72,
                                      message_length: byte_size(binary_data),
                                      message_type_id: 3,
                                      message_stream_id: 55}
    
    
    previous_headers = Map.put(%{}, 50, previous_header)    
    {:ok, socket} = __MODULE__.Mock.start_type_3_chunk(binary_data)
                                          
    {:ok, {_, _, ^binary_data}} = RtmpCommon.Chunking.read_next_chunk(socket, transport, previous_headers)
  end
  
  test "Error when no previous header for stream id and chunk type is 2", %{transport: transport, binary_data: binary_data} do
    {:ok, socket} = __MODULE__.Mock.start_type_2_chunk(binary_data)
    
    {:error, :no_previous_chunk} = RtmpCommon.Chunking.read_next_chunk(socket, transport, %{})
  end  
  
  test "Error when no previous header for stream id and chunk type is 3", %{transport: transport, binary_data: binary_data} do
    {:ok, socket} = __MODULE__.Mock.start_type_3_chunk(binary_data)
    
    {:error, :no_previous_chunk} = RtmpCommon.Chunking.read_next_chunk(socket, transport, %{})
  end  
  
  defp create_repeated_binary(byte, count) do
    List.duplicate(byte, count)
    |> IO.iodata_to_binary
  end
  
  defmodule Mock do
    def start_type_0_chunk(binary_data) do
      length = byte_size(binary_data)
      <<0::2, 50::6, 72::size(3)-unit(8), length::size(3)-unit(8), 3::8, 55::size(4)-unit(8)>> <> binary_data
      |> BinaryTransportMock.start_link
    end
    
    def start_type_1_chunk(binary_data) do
      length = byte_size(binary_data)
      <<1::2, 50::6, 72::size(3)-unit(8), length::size(3)-unit(8), 3::8>> <> binary_data
      |> BinaryTransportMock.start_link
    end
    
    def start_type_2_chunk(binary_data) do
      <<2::2, 50::6, 72::size(3)-unit(8)>> <> binary_data
      |> BinaryTransportMock.start_link
    end
    
    def start_type_3_chunk(binary_data) do
      <<3::2, 50::6>> <> binary_data
      |> BinaryTransportMock.start_link
    end
  end
end