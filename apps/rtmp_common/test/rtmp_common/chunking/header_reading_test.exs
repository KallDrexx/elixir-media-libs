defmodule RtmpCommon.Chunking.HeaderReadingTest do
  use ExUnit.Case, async: true
  alias RtmpCommon.Chunking.ChunkHeader, as: ChunkHeader
  
  setup do
    {:ok, transport: BinaryTransportMock}
  end
  
  test "Can read chunk header for valid type 0 chunk with basic header 1", %{transport: transport} do
    {:ok, socket} =  __MODULE__.Mock.start_valid_basic_1_type_0_chunk
    
    expected_header = %ChunkHeader{type: 0, 
                                      stream_id: 50,
                                      timestamp: 72,
                                      message_length: 100,
                                      message_type_id: 3,
                                      message_stream_id: 55}
                                      
    assert {:ok, {_, ^expected_header, _}} = RtmpCommon.Chunking.read_next_chunk(socket, transport, %{})
  end
  
  test "Can read chnk header for valid type 0 chunk with basic header 2", %{transport: transport} do
    {:ok, socket} =  __MODULE__.Mock.start_valid_basic_2_type_0_chunk
    
    expected_header = %ChunkHeader{type: 0, 
                                      stream_id: 264,
                                      timestamp: 72,
                                      message_length: 100,
                                      message_type_id: 3,
                                      message_stream_id: 55}
    
    assert {:ok, {_, ^expected_header, _}} = RtmpCommon.Chunking.read_next_chunk(socket, transport, %{})
  end
  
  test "Can read valid header for type 0 chunk with basic header 3", %{transport: transport} do
    {:ok, socket} =  __MODULE__.Mock.start_valid_basic_3_type_0_chunk
    
    expected_header = %ChunkHeader{type: 0, 
                                      stream_id: 60065,
                                      timestamp: 72,
                                      message_length: 100,
                                      message_type_id: 3,
                                      message_stream_id: 55}
    
    assert {:ok, {_, ^expected_header, _}} = RtmpCommon.Chunking.read_next_chunk(socket, transport, %{})
  end
  
  test "Can read valid header for type 1 chunk", %{transport: transport} do
    {:ok, socket} =  __MODULE__.Mock.start_valid_type_1_chunk
    
    previous_headers = Map.put(%{}, 50, %ChunkHeader{
      type: 0, 
      stream_id: 50,
      timestamp: 100,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    })
    
    expected_header = %ChunkHeader{
      type: 1, 
      stream_id: 50,
      timestamp: 172,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
                                         
    assert {:ok, {_, ^expected_header, _}} = RtmpCommon.Chunking.read_next_chunk(socket, transport, previous_headers)
  end
  
  test "Can read valid header for type 2 chunk", %{transport: transport} do
    {:ok, socket} =  __MODULE__.Mock.start_valid_type_2_chunk
    
    previous_headers = Map.put(%{}, 50, %ChunkHeader{
      type: 0, 
      stream_id: 50,
      timestamp: 100,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    })
    
    expected_header = %ChunkHeader{
      type: 2, 
      stream_id: 50,
      timestamp: 172,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
                                      
    assert {:ok, {_, ^expected_header, _}} = RtmpCommon.Chunking.read_next_chunk(socket, transport, previous_headers)
  end
  
  test "Can read valid header for type 3 chunk", %{transport: transport} do
    {:ok, socket} =  __MODULE__.Mock.start_valid_type_3_chunk
     
    expected_header = %ChunkHeader{type: 3, 
                                      stream_id: 50,
                                      timestamp: 72,
                                      message_length: 100,
                                      message_type_id: 3,
                                      message_stream_id: 55}
                                      
    previous_headers = Map.put(%{}, 50, expected_header)
    
    assert {:ok, {_, ^expected_header, _}} = RtmpCommon.Chunking.read_next_chunk(socket, transport, previous_headers)
  end
  
  test "Can read valid header for type 0 chunk with extended timestamp header", %{transport: transport} do
    {:ok, socket} =  __MODULE__.Mock.start_valid_type_0_chunk_with_extended_header
    
    expected_header = %ChunkHeader{type: 0, 
                                      stream_id: 50,
                                      timestamp: 16777216,
                                      message_length: 100,
                                      message_type_id: 3,
                                      message_stream_id: 55}
    
    assert {:ok, {_, ^expected_header, _}} = RtmpCommon.Chunking.read_next_chunk(socket, transport, %{})
  end
  
  test "Can read valid header for type 1 chunk with extended timestamp header", %{transport: transport} do
    {:ok, socket} =  __MODULE__.Mock.start_valid_type_1_chunk_with_extended_header
    
    previous_headers = Map.put(%{}, 50, %ChunkHeader{
      type: 0, 
      stream_id: 50,
      timestamp: 100,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    })
    
    expected_header = %ChunkHeader{type: 1, 
                                      stream_id: 50,
                                      timestamp: 16777316,
                                      message_length: 100,
                                      message_type_id: 3,
                                      message_stream_id: 55}
    
    assert {:ok, {_, ^expected_header, _}} = RtmpCommon.Chunking.read_next_chunk(socket, transport, previous_headers)
  end
  
  test "Can read valid header for type 2 chunk with extended timestamp header", %{transport: transport} do
    {:ok, socket} = __MODULE__.Mock.start_valid_type_2_chunk_with_extended_header
    
    previous_headers = Map.put(%{}, 50, %ChunkHeader{
      type: 0, 
      stream_id: 50,
      timestamp: 100,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    })
    
    expected_header = %ChunkHeader{type: 2, 
                                      stream_id: 50,
                                      timestamp: 16777316,
                                      message_length: 100,
                                      message_type_id: 3,
                                      message_stream_id: 55}
    
    assert {:ok, {_, ^expected_header, _}} = RtmpCommon.Chunking.read_next_chunk(socket, transport, previous_headers)
  end
  
  defmodule Mock do      
    def start_valid_basic_1_type_0_chunk do
      <<0::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8,
        55::size(4)-unit(8), <<152::size(100)-unit(8)>> >>
      |> BinaryTransportMock.start_link
    end
    
    def start_valid_basic_2_type_0_chunk do
      <<0::2, 0::6, 200::8, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8,
        55::size(4)-unit(8), <<152::size(100)-unit(8)>> >>
      |> BinaryTransportMock.start_link
    end
    
    def start_valid_basic_3_type_0_chunk do
      <<0::2, 1::6, 60001::16, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8,
        55::size(4)-unit(8), <<152::size(100)-unit(8)>> >>
      |> BinaryTransportMock.start_link
    end
    
    def start_valid_type_1_chunk do
      <<1::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8, <<152::size(100)-unit(8)>> >>
      |> BinaryTransportMock.start_link
    end
    
    def start_valid_type_2_chunk do
      <<2::2, 50::6, 72::size(3)-unit(8), <<152::size(100)-unit(8)>> >>
      |> BinaryTransportMock.start_link
    end
    
    def start_valid_type_3_chunk do
      <<3::2, 50::6, <<152::size(100)-unit(8)>> >>
      |> BinaryTransportMock.start_link
    end
    
    def start_valid_type_0_chunk_with_extended_header do
      <<0::2, 50::6, 16777215::size(3)-unit(8), 100::size(3)-unit(8), 3::8,
        55::size(4)-unit(8), 1::size(4)-unit(8), <<152::size(100)-unit(8)>> >>
      |> BinaryTransportMock.start_link
    end
    
    def start_valid_type_1_chunk_with_extended_header do
      <<1::2, 50::6, 16777215::size(3)-unit(8), 100::size(3)-unit(8), 3::8,
        1::size(4)-unit(8), <<152::size(100)-unit(8)>> >>
      |> BinaryTransportMock.start_link
    end
    
    def start_valid_type_2_chunk_with_extended_header do
      <<2::2, 50::6, 16777215::size(3)-unit(8), 1::size(4)-unit(8), <<152::size(100)-unit(8)>> >>
      |> BinaryTransportMock.start_link
    end
  end
end