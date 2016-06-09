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
    {handshake, _} = RtmpHandshake.new()
    
    # packet 0
    assert {handshake, %RtmpHandshake.ParseResult{
      current_state: :waiting_for_data, 
      bytes_to_send: <<>>
    }} = RtmpHandshake.process_bytes(handshake, <<3>>)

    # packet 1
    assert {handshake, %RtmpHandshake.ParseResult{
      current_state: :waiting_for_data,
      bytes_to_send: <<1::4 * 8, time::4 * 8, random::1528 * 8>>
    }} = RtmpHandshake.process_bytes(handshake, <<1::4 * 8, 0::4 * 8, 555::1528 * 8>>)

    # packet 2
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
end
