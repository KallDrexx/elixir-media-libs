defmodule RtmpCommon.Chunking.ReaderTest do
  use ExUnit.Case, async: true
  
  test "Can read valid type 0 chunk with basic header 1" do
    transport = __MODULE__.Mock
    {:ok, socket} = transport.start_valid_basic_1_type_0_chunk
    
    {:ok, %RtmpCommon.Chunking.ChunkHeader{type: 0, 
                                      stream_id: 50,
                                      timestamp: 72,
                                      message_length: 100,
                                      message_type_id: 3,
                                      message_stream_id: 55
    }}  = RtmpCommon.Chunking.HeaderReader.read(socket, transport)
  end
  
  test "Can read valid type 0 chunk with basic header 2" do
    transport = __MODULE__.Mock
    {:ok, socket} = transport.start_valid_basic_2_type_0_chunk
    
    {:ok, %RtmpCommon.Chunking.ChunkHeader{type: 0, 
                                      stream_id: 264,
                                      timestamp: 72,
                                      message_length: 100,
                                      message_type_id: 3,
                                      message_stream_id: 55
    }}  = RtmpCommon.Chunking.HeaderReader.read(socket, transport)
  end
  
  test "Can read valid type 0 chunk with basic header 3" do
    transport = __MODULE__.Mock
    {:ok, socket} = transport.start_valid_basic_3_type_0_chunk
    
    {:ok, %RtmpCommon.Chunking.ChunkHeader{type: 0, 
                                      stream_id: 60065,
                                      timestamp: 72,
                                      message_length: 100,
                                      message_type_id: 3,
                                      message_stream_id: 55
    }}  = RtmpCommon.Chunking.HeaderReader.read(socket, transport)
  end
  
  test "Can read valid type 1 chunk with basic header 1" do
    transport = __MODULE__.Mock
    {:ok, socket} = transport.start_valid_basic_1_type_1_chunk
    
    {:ok, %RtmpCommon.Chunking.ChunkHeader{type: 1, 
                                      stream_id: 50,
                                      timestamp: 72,
                                      message_length: 100,
                                      message_type_id: 3,
                                      message_stream_id: nil
    }}  = RtmpCommon.Chunking.HeaderReader.read(socket, transport)
  end
  
  test "Can read valid type 2 chunk with basic header 1" do
    transport = __MODULE__.Mock
    {:ok, socket} = transport.start_valid_basic_1_type_2_chunk
    
    {:ok, %RtmpCommon.Chunking.ChunkHeader{type: 2, 
                                      stream_id: 50,
                                      timestamp: 72,
                                      message_length: nil,
                                      message_type_id: nil,
                                      message_stream_id: nil
    }}  = RtmpCommon.Chunking.HeaderReader.read(socket, transport)
  end
  
  test "Can read valid type 3 chunk with basic header 1" do
    transport = __MODULE__.Mock
    {:ok, socket} = transport.start_valid_basic_1_type_3_chunk
    
    {:ok, %RtmpCommon.Chunking.ChunkHeader{type: 3, 
                                      stream_id: 50,
                                      timestamp: nil,
                                      message_length: nil,
                                      message_type_id: nil,
                                      message_stream_id: nil
    }}  = RtmpCommon.Chunking.HeaderReader.read(socket, transport)
  end
  
  defmodule Mock do   
    def start_valid_basic_1_type_0_chunk do
      <<0::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8,
        55::size(4)-unit(8)>>
      |> start_link
    end
    
    def start_valid_basic_2_type_0_chunk do
      <<0::2, 0::6, 200::8, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8,
        55::size(4)-unit(8)>>
      |> start_link
    end
    
    def start_valid_basic_3_type_0_chunk do
      <<0::2, 1::6, 60001::16, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8,
        55::size(4)-unit(8)>>
      |> start_link
    end
    
    def start_valid_basic_1_type_1_chunk do
      <<1::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8,
        55::size(4)-unit(8)>>
      |> start_link
    end
    
    def start_valid_basic_1_type_2_chunk do
      <<2::2, 50::6, 72::size(3)-unit(8)>>
      |> start_link
    end
    
    def start_valid_basic_1_type_3_chunk do
      <<3::2, 50::6>>
      |> start_link
    end
    
    def recv(agent, num_bytes, _timeout) do
      binary = Agent.get(agent, fn state -> state end)
      case do_recv(num_bytes, binary, <<>>) do
        {:error, reason} -> {:error, reason}
        {result, remaining_binary} ->
          Agent.update(agent, fn _ -> remaining_binary end)
          {:ok, result}
      end
    end
    
    defp do_recv(0, binary, acc), do: {acc, binary}
    defp do_recv(_, <<>>, _), do: {:error, :timeout}
    defp do_recv(num_bytes, binary, acc) do
      <<byte::8, rest::binary>> = binary
      do_recv(num_bytes - 1, rest, acc <> <<byte>>)
    end
    
    defp start_link(binary) do
      Agent.start_link(fn -> binary end)
    end
  end
end