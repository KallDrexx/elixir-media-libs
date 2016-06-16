defmodule RtmpSession.ChunkIoTest do
  use ExUnit.Case, async: true
  alias RtmpSession.Messages.RtmpMessage, as: RtmpMessage
  alias RtmpSession.ChunkIo, as: ChunkIo

  @previous_chunk_0_binary <<0::2, 50::6, 100::size(3)-unit(8), 100::size(3)-unit(8), 3::8, 55::size(4)-unit(8), 152::size(100)-unit(8)>>
  @previous_chunk_1_binary <<1::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8, 152::size(100)-unit(8)>>

  test "Can read full type 0 chunk with small chunk stream id" do
    binary = <<0::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8, 55::size(4)-unit(8), 152::size(100)-unit(8)>>
    result = ChunkIo.new() |> ChunkIo.deserialize(binary)

    assert {_, %RtmpMessage{
      timestamp: 72,
      message_type_id: 3,
      payload: <<152::100 * 8>>
    }} = result
  end

  test "Can read full type 0 chunk with medium chunk stream id" do
    binary = <<0::2, 0::6, 200::8, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8, 55::size(4)-unit(8), 152::size(100)-unit(8)>>
    result = ChunkIo.new() |> ChunkIo.deserialize(binary)

    assert {_, %RtmpMessage{
      timestamp: 72,
      message_type_id: 3,
      payload: <<152::100 * 8>>
    }} = result
  end

  test "Can read full type 0 chunk with large chunk stream id" do
    binary = <<0::2, 1::6, 60001::16, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8, 55::size(4)-unit(8), 152::size(100)-unit(8)>>
    result = ChunkIo.new() |> ChunkIo.deserialize(binary)

    assert {_, %RtmpMessage{
      timestamp: 72,
      message_type_id: 3,
      payload: <<152::100 * 8>>
    }} = result
  end

  test "Can read full type 1 chunk" do
    binary = <<1::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8, 152::size(100)-unit(8)>>
    
    assert {io, %RtmpMessage{}} = ChunkIo.new() |> ChunkIo.deserialize(@previous_chunk_0_binary)
    assert {_, %RtmpMessage{
      timestamp: 172,
      message_type_id: 3,
      payload: <<152::100 * 8>>
    }} = ChunkIo.deserialize(io, binary)
  end

  test "Can read full type 2 chunk" do
    binary = <<2::2, 50::6, 72::size(3)-unit(8), 152::size(100)-unit(8)>>
    
    assert {io, %RtmpMessage{}} = ChunkIo.new() |> ChunkIo.deserialize(@previous_chunk_0_binary)
    assert {_, %RtmpMessage{
      timestamp: 172,
      message_type_id: 3,
      payload: <<152::100 * 8>>
    }} = ChunkIo.deserialize(io, binary)
  end

  test "Can read full type 3 chunk" do
    binary = <<3::2, 50::6, 152::size(100)-unit(8)>>
    
    assert {io, %RtmpMessage{}} = ChunkIo.new() |> ChunkIo.deserialize(@previous_chunk_0_binary)
    assert {io, %RtmpMessage{}} = ChunkIo.deserialize(io, @previous_chunk_1_binary)
    assert {_, %RtmpMessage{
      timestamp: 244,
      message_type_id: 3,
      payload: <<152::100 * 8>>
    }} = ChunkIo.deserialize(io, binary)
  end

  test "Can read full type 0 chunk with extended timestamp" do
    binary = <<0::2, 50::6, 16777215::size(3)-unit(8), 100::size(3)-unit(8), 3::8, 55::size(4)-unit(8), 1::size(4)-unit(8), 152::size(100)-unit(8)>>
    result = ChunkIo.new() |> ChunkIo.deserialize(binary)

    assert {_, %RtmpMessage{
      timestamp: 16777216,
      message_type_id: 3,
      payload: <<152::100 * 8>>
    }} = result
  end

  test "Can read full type 1 chunk with extended timestamp" do
    binary = <<1::2, 50::6, 16777215::size(3)-unit(8), 100::size(3)-unit(8), 3::8, 1::size(4)-unit(8), 152::size(100)-unit(8)>>

    assert {io, %RtmpMessage{}} = ChunkIo.new() |> ChunkIo.deserialize(@previous_chunk_0_binary)
    assert {_, %RtmpMessage{
      timestamp: 16777316,
      message_type_id: 3,
      payload: <<152::100 * 8>>
    }} = ChunkIo.deserialize(io, binary)
  end

  test "Can read full type 2 chunk with extended timestamp" do
    binary = <<2::2, 50::6, 16777215::size(3)-unit(8), 1::size(4)-unit(8), 152::size(100)-unit(8)>>

    assert {io, %RtmpMessage{}} = ChunkIo.new() |> ChunkIo.deserialize(@previous_chunk_0_binary)
    assert {_, %RtmpMessage{
      timestamp: 16777316,
      message_type_id: 3,
      payload: <<152::100 * 8>>
    }} = ChunkIo.deserialize(io, binary)
  end

  test "Incomplete chunk returns incomplete notification" do
    binary = <<0::2, 50::6, 100::size(3)-unit(8), 100::size(3)-unit(8)>>

    assert {_, :incomplete} = ChunkIo.new() |> ChunkIo.deserialize(binary)
  end

  test "Can read message spread across multiple deserialization calls" do
    binary1 = <<0::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 3::8>>
    binary2 = <<55::size(4)-unit(8), 0::size(90)-unit(8)>>
    binary3 = <<152::size(10)-unit(8)>>

    io = ChunkIo.new()
    assert {io, :incomplete} = ChunkIo.deserialize(io, binary1)
    assert {io, :incomplete} = ChunkIo.deserialize(io, binary2)
    assert {_, %RtmpMessage{
      timestamp: 72,
      message_type_id: 3,
      payload: <<152::100 * 8>>
    }} = ChunkIo.deserialize(io, binary3)
  end

end