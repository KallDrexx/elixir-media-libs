defmodule RtmpHandshakeTest do
  use ExUnit.Case
  require Logger

  test "Initial creation of handshake returns packet 0" do
    assert {
      _, 
      %RtmpHandshake.ParseResult{
        current_state: :waiting_for_data,
        bytes_to_send: <<3::8, _::binary>>} 
      }  
      = RtmpHandshake.new()
  end

  test "Initial creation of handshake returns packet 1" do
    assert {_, %RtmpHandshake.ParseResult{
      current_state: :waiting_for_data,
      bytes_to_send: <<_::8, _::4 * 8, 0::4 * 8, _::1528 * 8>>} 
    }  
    = RtmpHandshake.new()
  end

  test "Can parse full handshake" do
    {handshake, %RtmpHandshake.ParseResult{
      current_state: :waiting_for_data,
      bytes_to_send: <<3::1 * 8, time::4 * 8, 0::4 * 8, random::1528 * 8>>
    }} = RtmpHandshake.new()
    
    # send packet 0
    assert {handshake, %RtmpHandshake.ParseResult{
      current_state: :waiting_for_data, 
      bytes_to_send: <<>>
    }} = RtmpHandshake.process_bytes(handshake, <<3>>)

    # send packet 1
    assert {handshake, %RtmpHandshake.ParseResult{
      current_state: :waiting_for_data,
      bytes_to_send: <<1::4 * 8, 0::4 * 8, 555::1528 * 8>> # their p2 should match my p1
    }} = RtmpHandshake.process_bytes(handshake, <<1::4 * 8, 0::4 * 8, 555::1528 * 8>>)

    # send packet 2
    assert {handshake, %RtmpHandshake.ParseResult{
      current_state: :success,
      bytes_to_send: <<>>
    }} = RtmpHandshake.process_bytes(handshake, <<time::4 * 8, 1::4 * 8, random::1528 * 8>>)

    # final result
    assert {_, %RtmpHandshake.HandshakeResult{
      peer_start_timestamp: 1,
      remaining_binary: <<>>
    }} = RtmpHandshake.get_handshake_result(handshake)
  end

  test "Two handshake instances can complete handshake against each other" do
    {handshake1, %RtmpHandshake.ParseResult{bytes_to_send: bytes1_1}} = RtmpHandshake.new()
    {handshake2, %RtmpHandshake.ParseResult{bytes_to_send: bytes2_1}} = RtmpHandshake.new()

    # packets 0 and 1
    assert {handshake1, %RtmpHandshake.ParseResult{current_state: :waiting_for_data, bytes_to_send: bytes1_2}}
      = RtmpHandshake.process_bytes(handshake1, bytes2_1)

    assert {handshake2, %RtmpHandshake.ParseResult{current_state: :waiting_for_data, bytes_to_send: bytes2_2}}
      = RtmpHandshake.process_bytes(handshake2, bytes1_1)

    Logger.debug "bytes1_2: #{inspect(bytes1_2)}"
    Logger.debug "bytes2_2: #{inspect(bytes2_2)}"

    # packet 2
    assert {_, %RtmpHandshake.ParseResult{current_state: :success}}
      = RtmpHandshake.process_bytes(handshake1, bytes2_2)

    assert {_, %RtmpHandshake.ParseResult{current_state: :success}}
      = RtmpHandshake.process_bytes(handshake2, bytes1_2)
  end
end
