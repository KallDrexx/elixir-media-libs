defmodule RtmpHandshakeTest do
  use ExUnit.Case, async: true
  require Logger

  test "Initial creation of handshake with old format specified returns packet 0" do
    assert {
      _, 
      %RtmpHandshake.ParseResult{
        current_state: :waiting_for_data,
        bytes_to_send: <<3::8, _::binary>>} 
      }  
      = RtmpHandshake.new(:old)
  end

  test "Initial creation of handshake with old format specified returns packet 1" do
    assert {_, %RtmpHandshake.ParseResult{
      current_state: :waiting_for_data,
      bytes_to_send: <<_::8, _::4 * 8, 0::4 * 8, _::1528 * 8>>} 
    }  
    = RtmpHandshake.new(:old)
  end

  test "Can parse full old format handshake" do
    assert {handshake, %RtmpHandshake.ParseResult{
      current_state: :waiting_for_data,
      bytes_to_send: <<3::1 * 8, time::4 * 8, 0::4 * 8, random::1528 * 8>>
    }} = RtmpHandshake.new(:old)
    
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

  test "Two old handshake instances can complete handshake against each other" do
    {handshake1, %RtmpHandshake.ParseResult{bytes_to_send: bytes1_1}} = RtmpHandshake.new(:old)
    {handshake2, %RtmpHandshake.ParseResult{bytes_to_send: bytes2_1}} = RtmpHandshake.new(:old)

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

  test "Handshakes with unknown format specified do not send p0 and p1 until they receive p0 and p1" do
    assert {handshake, %RtmpHandshake.ParseResult{
      current_state: :waiting_for_data,
      bytes_to_send: <<>>
    }} = RtmpHandshake.new(:unknown)

    assert {handshake, %RtmpHandshake.ParseResult{
      current_state: :waiting_for_data,
      bytes_to_send: <<>>
    }} = RtmpHandshake.process_bytes(handshake, <<3>>)

    assert {_, %RtmpHandshake.ParseResult{
      current_state: :waiting_for_data,
      bytes_to_send: <<3::1 * 8, _::4 * 8, 0::4 * 8, _::1528 * 8, _::binary>>
    }} = RtmpHandshake.process_bytes(handshake, <<1::4 * 8, 0::4 * 8, 555::1528 * 8>>)
  end

end
