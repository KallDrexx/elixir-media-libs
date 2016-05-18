defmodule RtmpCommon.Chunking.DeserializerTest do
  use ExUnit.Case, async: true
  alias RtmpCommon.Chunking.ChunkHeader, as: ChunkHeader
  alias RtmpCommon.Chunking.Deserializer, as: Deserializer
  
  @previous_chunk_0_binary <<0::2, 50::6, 100::size(3)-unit(8), 100::size(3)-unit(8), 3::8, 55::size(4)-unit(8), 152::size(100)-unit(8)>>
  @previous_chunk_1_binary <<1::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8, 152::size(100)-unit(8)>>
  
  setup do
    constant = 1
    mfa = {__MODULE__, :send_result, [constant]}
    {:ok, mfa: mfa, constant: constant}
  end
  
  test "Can read full type 0 chunk with format 1 basic header", %{mfa: mfa, constant: constant} do
    Deserializer.new(mfa)
    |> Deserializer.process(<<0::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8>>)
    |> Deserializer.process(<<55::size(4)-unit(8), 152::size(100)-unit(8)>>)
    
    expected_header = %ChunkHeader{
      type: 0, 
      stream_id: 50,
      timestamp: 72,
      last_timestamp_delta: 0,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert_receive {^constant, ^expected_header, <<152::size(100)-unit(8)>>}
  end
  
  test "Can read full type 0 chunk with format 2 basic header", %{mfa: mfa, constant: constant} do
    Deserializer.new(mfa)
    |> Deserializer.process(<<0::2, 0::6, 200::8, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8>>)
    |> Deserializer.process(<<55::size(4)-unit(8), 152::size(100)-unit(8)>>)
    
    expected_header = %ChunkHeader{
      type: 0, 
      stream_id: 264,
      timestamp: 72,
      last_timestamp_delta: 0,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert_receive {^constant, ^expected_header, <<152::size(100)-unit(8)>>}
  end
  
  test "Can read full type 0 chunk with format 3 basic header", %{mfa: mfa, constant: constant} do
    Deserializer.new(mfa)
    |> Deserializer.process(<<0::2, 1::6, 60001::16, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8>>)
    |> Deserializer.process(<<55::size(4)-unit(8), 152::size(100)-unit(8)>>)
    
    expected_header = %ChunkHeader{
      type: 0, 
      stream_id: 60065,
      timestamp: 72,
      last_timestamp_delta: 0,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert_receive {^constant, ^expected_header, <<152::size(100)-unit(8)>>}
  end
  
  test "Can read full type 1 chunk", %{mfa: mfa, constant: constant} do
    Deserializer.new(mfa)    
    |> Deserializer.process(@previous_chunk_0_binary)
    |> Deserializer.process(<<1::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8, 152::size(100)-unit(8)>>)
    
    expected_header = %ChunkHeader{
      type: 1, 
      stream_id: 50,
      timestamp: 172,
      last_timestamp_delta: 72,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert_receive {^constant, _, _}
    assert_receive {^constant, ^expected_header, <<152::size(100)-unit(8)>>}
  end
  
  test "Can read full type 2 chunk", %{mfa: mfa, constant: constant} do
    Deserializer.new(mfa)    
    |> Deserializer.process(@previous_chunk_0_binary)
    |> Deserializer.process(<<2::2, 50::6, 72::size(3)-unit(8), 152::size(100)-unit(8)>>)
    
    expected_header = %ChunkHeader{
      type: 2, 
      stream_id: 50,
      timestamp: 172,
      last_timestamp_delta: 72,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert_receive {^constant, _, _}
    assert_receive {^constant, ^expected_header, <<152::size(100)-unit(8)>>}
  end
  
  test "Can read full type 3 chunk", %{mfa: mfa, constant: constant} do
    Deserializer.new(mfa)    
    |> Deserializer.process(@previous_chunk_0_binary)
    |> Deserializer.process(@previous_chunk_1_binary)
    |> Deserializer.process(<<3::2, 50::6, 152::size(100)-unit(8)>>)
    
    expected_header = %ChunkHeader{
      type: 3, 
      stream_id: 50,
      timestamp: 244,
      last_timestamp_delta: 72,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert_receive {^constant, _, _}
    assert_receive {^constant, ^expected_header, <<152::size(100)-unit(8)>>}
  end
  
  test "Can read type 0 chunk with extended timestamp", %{mfa: mfa, constant: constant} do
    Deserializer.new(mfa)
    |> Deserializer.process(<<0::2, 50::6, 16777215::size(3)-unit(8), 100::size(3)-unit(8), 3::8>>)
    |> Deserializer.process(<<55::size(4)-unit(8), 1::size(4)-unit(8), 152::size(100)-unit(8)>>)
    
    expected_header = %ChunkHeader{
      type: 0, 
      stream_id: 50,
      timestamp: 16777216,
      last_timestamp_delta: 0,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert_receive {^constant, ^expected_header, <<152::size(100)-unit(8)>>}
  end
  
  test "Can read type 1 chunk with extended timestamp", %{mfa: mfa, constant: constant} do
    Deserializer.new(mfa)
    |> Deserializer.process(@previous_chunk_0_binary)
    |> Deserializer.process(<<1::2, 50::6, 16777215::size(3)-unit(8), 100::size(3)-unit(8), 3::8, 1::size(4)-unit(8), 152::size(100)-unit(8)>>)
    
    expected_header = %ChunkHeader{
      type: 1, 
      stream_id: 50,
      timestamp: 16777316,
      last_timestamp_delta: 16777216,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert_receive {^constant, ^expected_header, <<152::size(100)-unit(8)>>}
  end
  
  test "Can read type 2 chunk with extended timestamp", %{mfa: mfa, constant: constant} do
    Deserializer.new(mfa)
    |> Deserializer.process(@previous_chunk_0_binary)
    |> Deserializer.process(<<2::2, 50::6, 16777215::size(3)-unit(8), 1::size(4)-unit(8), 152::size(100)-unit(8)>>)
    
    expected_header = %ChunkHeader{
      type: 2, 
      stream_id: 50,
      timestamp: 16777316,
      last_timestamp_delta: 16777216,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert_receive {^constant, ^expected_header, <<152::size(100)-unit(8)>>}
  end
  
  def send_result(constant, header, data) do
    send(self(), {constant, header, data})
  end
end