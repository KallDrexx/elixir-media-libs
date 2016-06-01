defmodule RtmpCommon.Chunking.DeserializerTest do
  use ExUnit.Case, async: true
  alias RtmpCommon.Chunking.ChunkHeader, as: ChunkHeader
  alias RtmpCommon.Chunking.Deserializer, as: Deserializer
  
  @previous_chunk_0_binary <<0::2, 50::6, 100::size(3)-unit(8), 100::size(3)-unit(8), 3::8, 55::size(4)-unit(8), 152::size(100)-unit(8)>>
  @previous_chunk_1_binary <<1::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8, 152::size(100)-unit(8)>>
  
  test "Can read full type 0 chunk with format 1 basic header" do
    {_, [{header, data}]} =
      Deserializer.new()
      |> Deserializer.process(<<0::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8>>)
      |> Deserializer.process(<<55::size(4)-unit(8), 152::size(100)-unit(8)>>)
      |> Deserializer.get_deserialized_chunks()
    
    expected_header = %ChunkHeader{
      type: 0, 
      stream_id: 50,
      timestamp: 72,
      last_timestamp_delta: 0,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert expected_header == header
    assert <<152::size(100)-unit(8)>> == data
  end
  
  test "Can read full type 0 chunk with format 2 basic header" do
    {_, [{header, data}]} =
      Deserializer.new()
      |> Deserializer.process(<<0::2, 0::6, 200::8, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8>>)
      |> Deserializer.process(<<55::size(4)-unit(8), 152::size(100)-unit(8)>>)
      |> Deserializer.get_deserialized_chunks()
    
    expected_header = %ChunkHeader{
      type: 0, 
      stream_id: 264,
      timestamp: 72,
      last_timestamp_delta: 0,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert expected_header == header
    assert <<152::size(100)-unit(8)>> == data
  end
  
  test "Can read full type 0 chunk with format 3 basic header" do
    {_, [{header, data}]} =
      Deserializer.new()
      |> Deserializer.process(<<0::2, 1::6, 60001::16, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8>>)
      |> Deserializer.process(<<55::size(4)-unit(8), 152::size(100)-unit(8)>>)
      |> Deserializer.get_deserialized_chunks()
    
    expected_header = %ChunkHeader{
      type: 0, 
      stream_id: 60065,
      timestamp: 72,
      last_timestamp_delta: 0,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert expected_header == header
    assert <<152::size(100)-unit(8)>> == data
  end
  
  test "Can read full type 1 chunk" do
    {_, [_, {header, data}]} =
      Deserializer.new()    
      |> Deserializer.process(@previous_chunk_0_binary)
      |> Deserializer.process(<<1::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8, 152::size(100)-unit(8)>>)
      |> Deserializer.get_deserialized_chunks()
    
    expected_header = %ChunkHeader{
      type: 1, 
      stream_id: 50,
      timestamp: 172,
      last_timestamp_delta: 72,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert expected_header == header
    assert <<152::size(100)-unit(8)>> == data
  end
  
  test "Can read full type 2 chunk" do
    {_, [_, {header, data}]} =
      Deserializer.new()    
      |> Deserializer.process(@previous_chunk_0_binary)
      |> Deserializer.process(<<2::2, 50::6, 72::size(3)-unit(8), 152::size(100)-unit(8)>>)
      |> Deserializer.get_deserialized_chunks()
    
    expected_header = %ChunkHeader{
      type: 2, 
      stream_id: 50,
      timestamp: 172,
      last_timestamp_delta: 72,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert expected_header == header
    assert <<152::size(100)-unit(8)>> == data
  end
  
  test "Can read full type 3 chunk" do
    {_, [_, _, {header, data}]} =
      Deserializer.new()    
      |> Deserializer.process(@previous_chunk_0_binary)
      |> Deserializer.process(@previous_chunk_1_binary)
      |> Deserializer.process(<<3::2, 50::6, 152::size(100)-unit(8)>>)
      |> Deserializer.get_deserialized_chunks()
    
    expected_header = %ChunkHeader{
      type: 3, 
      stream_id: 50,
      timestamp: 244,
      last_timestamp_delta: 72,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert expected_header == header
    assert <<152::size(100)-unit(8)>> == data
  end
  
  test "Can read type 0 chunk with extended timestamp" do
    {_, [{header, data}]} =
      Deserializer.new()
      |> Deserializer.process(<<0::2, 50::6, 16777215::size(3)-unit(8), 100::size(3)-unit(8), 3::8>>)
      |> Deserializer.process(<<55::size(4)-unit(8), 1::size(4)-unit(8), 152::size(100)-unit(8)>>)
      |> Deserializer.get_deserialized_chunks()
    
    expected_header = %ChunkHeader{
      type: 0, 
      stream_id: 50,
      timestamp: 16777216,
      last_timestamp_delta: 0,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert expected_header == header
    assert <<152::size(100)-unit(8)>> == data
  end
  
  test "Can read type 1 chunk with extended timestamp" do
    {_, [_, {header, data}]} =
      Deserializer.new()
      |> Deserializer.process(@previous_chunk_0_binary)
      |> Deserializer.process(<<1::2, 50::6, 16777215::size(3)-unit(8), 100::size(3)-unit(8), 3::8, 1::size(4)-unit(8), 152::size(100)-unit(8)>>)
      |> Deserializer.get_deserialized_chunks()
    
    expected_header = %ChunkHeader{
      type: 1, 
      stream_id: 50,
      timestamp: 16777316,
      last_timestamp_delta: 16777216,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert expected_header == header
    assert <<152::size(100)-unit(8)>> == data
  end
  
  test "Can read type 2 chunk with extended timestamp" do
    {_, [_, {header, data}]} =
      Deserializer.new()
      |> Deserializer.process(@previous_chunk_0_binary)
      |> Deserializer.process(<<2::2, 50::6, 16777215::size(3)-unit(8), 1::size(4)-unit(8), 152::size(100)-unit(8)>>)
      |> Deserializer.get_deserialized_chunks()
    
    expected_header = %ChunkHeader{
      type: 2, 
      stream_id: 50,
      timestamp: 16777316,
      last_timestamp_delta: 16777216,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert expected_header == header
    assert <<152::size(100)-unit(8)>> == data
  end
  
  test "Incomplete chunk does not return any chunks" do
    result = 
      Deserializer.new() 
      |> Deserializer.process(<<1>>)
      |> Deserializer.get_deserialized_chunks()
    
    assert {_, []} = result      
  end
  
  test "No chunks returned after successfully reading current chunks" do
    {instance, _} =
      Deserializer.new() 
      |> Deserializer.process(<<1>>)
      |> Deserializer.get_deserialized_chunks()
    
    result = Deserializer.get_deserialized_chunks(instance)
    
    assert {_, []} = result
  end
  
  test "Can read message spread across multiple chunks" do
    {_, [{header, data}]} =
      Deserializer.new()
      |> Deserializer.set_max_chunk_size(90)
      |> Deserializer.process(<<0::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8>>)
      |> Deserializer.process(<<55::size(4)-unit(8), 0::size(90)-unit(8)>>)
      |> Deserializer.process(<<3::2, 50::6, 152::size(10)-unit(8)>>)
      |> Deserializer.get_deserialized_chunks()
      
    expected_header = %ChunkHeader{
      type: 3, 
      stream_id: 50,
      timestamp: 72,
      last_timestamp_delta: 0,
      message_length: 100,
      message_type_id: 3,
      message_stream_id: 55
    }
    
    assert expected_header == header
    assert <<152::size(100)-unit(8)>> == data
  end
  
  test "Status of processing while parsable binary exists for 2nd chunk after initial processing" do
    status = 
      Deserializer.new()
      |> Deserializer.process(@previous_chunk_0_binary <> <<0::2, 50::6, 100::size(3)-unit(8), 100::size(3)-unit(8)>>)
      |> Deserializer.get_status
      
    assert :processing = status
  end
  
  test "Status of waiting_for_data when partial chunk passed in" do
    status = 
      Deserializer.new()
      |> Deserializer.process(<<0::2, 50::6, 100::size(3)-unit(8), 100::size(3)-unit(8)>>)
      |> Deserializer.get_status
      
    assert :waiting_for_data = status
  end
end