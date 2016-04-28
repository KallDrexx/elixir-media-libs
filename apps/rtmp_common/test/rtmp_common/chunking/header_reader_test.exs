defmodule RtmpCommon.Chunking.HeaderReaderTest do
  use ExUnit.Case, async: true
  
  setup do
    {:ok, transport: BinaryTransportMock}
  end
  
  test "Can read valid type 0 chunk with basic header 1", %{transport: transport} do
    {:ok, socket} =  __MODULE__.Mock.start_valid_basic_1_type_0_chunk
    
    {:ok, %RtmpCommon.Chunking.ChunkHeader{type: 0, 
                                      stream_id: 50,
                                      timestamp: 72,
                                      message_length: 100,
                                      message_type_id: 3,
                                      message_stream_id: 55
    }}  = RtmpCommon.Chunking.HeaderReader.read(socket, transport)
  end
  
  test "Can read valid type 0 chunk with basic header 2", %{transport: transport} do
    {:ok, socket} =  __MODULE__.Mock.start_valid_basic_2_type_0_chunk
    
    {:ok, %RtmpCommon.Chunking.ChunkHeader{type: 0, 
                                      stream_id: 264,
                                      timestamp: 72,
                                      message_length: 100,
                                      message_type_id: 3,
                                      message_stream_id: 55
    }}  = RtmpCommon.Chunking.HeaderReader.read(socket, transport)
  end
  
  test "Can read valid type 0 chunk with basic header 3", %{transport: transport} do
    {:ok, socket} =  __MODULE__.Mock.start_valid_basic_3_type_0_chunk
    
    {:ok, %RtmpCommon.Chunking.ChunkHeader{type: 0, 
                                      stream_id: 60065,
                                      timestamp: 72,
                                      message_length: 100,
                                      message_type_id: 3,
                                      message_stream_id: 55
    }}  = RtmpCommon.Chunking.HeaderReader.read(socket, transport)
  end
  
  test "Can read valid type 1 chunk", %{transport: transport} do
    {:ok, socket} =  __MODULE__.Mock.start_valid_type_1_chunk
    
    {:ok, %RtmpCommon.Chunking.ChunkHeader{type: 1, 
                                      stream_id: 50,
                                      timestamp: 72,
                                      message_length: 100,
                                      message_type_id: 3,
                                      message_stream_id: nil
    }}  = RtmpCommon.Chunking.HeaderReader.read(socket, transport)
  end
  
  test "Can read valid type 2 chunk", %{transport: transport} do
    {:ok, socket} =  __MODULE__.Mock.start_valid_type_2_chunk
    
    {:ok, %RtmpCommon.Chunking.ChunkHeader{type: 2, 
                                      stream_id: 50,
                                      timestamp: 72,
                                      message_length: nil,
                                      message_type_id: nil,
                                      message_stream_id: nil
    }}  = RtmpCommon.Chunking.HeaderReader.read(socket, transport)
  end
  
  test "Can read valid type 3 chunk", %{transport: transport} do
    {:ok, socket} =  __MODULE__.Mock.start_valid_type_3_chunk
    
    {:ok, %RtmpCommon.Chunking.ChunkHeader{type: 3, 
                                      stream_id: 50,
                                      timestamp: nil,
                                      message_length: nil,
                                      message_type_id: nil,
                                      message_stream_id: nil
    }}  = RtmpCommon.Chunking.HeaderReader.read(socket, transport)
  end
  
  test "Can read valid type 0 chunk with extended header", %{transport: transport} do
    {:ok, socket} =  __MODULE__.Mock.start_valid_type_0_chunk_with_extended_header
    
    {:ok, %RtmpCommon.Chunking.ChunkHeader{type: 0, 
                                      stream_id: 50,
                                      timestamp: 16777216,
                                      message_length: 100,
                                      message_type_id: 3,
                                      message_stream_id: 55
    }}  = RtmpCommon.Chunking.HeaderReader.read(socket, transport)
  end
  
  test "Can read valid type 1 chunk with extended header", %{transport: transport} do
    {:ok, socket} =  __MODULE__.Mock.start_valid_type_1_chunk_with_extended_header
    
    {:ok, %RtmpCommon.Chunking.ChunkHeader{type: 1, 
                                      stream_id: 50,
                                      timestamp: 16777216,
                                      message_length: 100,
                                      message_type_id: 3,
                                      message_stream_id: nil
    }}  = RtmpCommon.Chunking.HeaderReader.read(socket, transport)
  end
  
  test "Can read valid type 2 chunk with extended header", %{transport: transport} do
    {:ok, socket} = __MODULE__.Mock.start_valid_type_2_chunk_with_extended_header
    
    {:ok, %RtmpCommon.Chunking.ChunkHeader{type: 2, 
                                      stream_id: 50,
                                      timestamp: 16777216,
                                      message_length: nil,
                                      message_type_id: nil,
                                      message_stream_id: nil
    }}  = RtmpCommon.Chunking.HeaderReader.read(socket, transport)
  end
  
  defmodule Mock do      
    def start_valid_basic_1_type_0_chunk do
      <<0::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8,
        55::size(4)-unit(8)>>
      |> BinaryTransportMock.start_link
    end
    
    def start_valid_basic_2_type_0_chunk do
      <<0::2, 0::6, 200::8, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8,
        55::size(4)-unit(8)>>
      |> BinaryTransportMock.start_link
    end
    
    def start_valid_basic_3_type_0_chunk do
      <<0::2, 1::6, 60001::16, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8,
        55::size(4)-unit(8)>>
      |> BinaryTransportMock.start_link
    end
    
    def start_valid_type_1_chunk do
      <<1::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8>>
      |> BinaryTransportMock.start_link
    end
    
    def start_valid_type_2_chunk do
      <<2::2, 50::6, 72::size(3)-unit(8)>>
      |> BinaryTransportMock.start_link
    end
    
    def start_valid_type_3_chunk do
      <<3::2, 50::6>>
      |> BinaryTransportMock.start_link
    end
    
    def start_valid_type_0_chunk_with_extended_header do
      <<0::2, 50::6, 16777215::size(3)-unit(8), 100::size(3)-unit(8), 3::8,
        55::size(4)-unit(8), 1::size(4)-unit(8)>>
      |> BinaryTransportMock.start_link
    end
    
    def start_valid_type_1_chunk_with_extended_header do
      <<1::2, 50::6, 16777215::size(3)-unit(8), 100::size(3)-unit(8), 3::8,
        1::size(4)-unit(8)>>
      |> BinaryTransportMock.start_link
    end
    
    def start_valid_type_2_chunk_with_extended_header do
      <<2::2, 50::6, 16777215::size(3)-unit(8), 1::size(4)-unit(8)>>
      |> BinaryTransportMock.start_link
    end
  end
end