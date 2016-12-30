defmodule Rtmp.Protocol.HandlerTest do
  use ExUnit.Case, async: true

  alias Rtmp.Protocol.Handler, as: ProtocolHandler
  alias Rtmp.Protocol.DetailedMessage, as: DetailedMessage
  alias Rtmp.Protocol.Messages.VideoData, as: VideoData

  test "Valid chunk 0 RTMP binary input deserialized and sent via session function" do
    session_function = fn(pid, message) -> send(pid, {:message, message}); :ok end
    input = <<0::2, 50::6, 72::size(3)-unit(8), 12::size(3)-unit(8), 9::8, 55::size(4)-unit(8)-little, 152::size(12)-unit(8)>>

    assert {:ok, handler} = ProtocolHandler.start_link("id", nil, nil)
    assert :ok = ProtocolHandler.set_session(handler, self(), session_function)
    assert :ok = ProtocolHandler.notify_input(handler, input)

    assert_receive {:message, %DetailedMessage{
      timestamp: 72,
      stream_id: 55,
      content: %VideoData{
        data: <<152::12 * 8>>
      }
    }}, 1000
  end

  test "Passed in message is serialized and sent to socket function" do
    socket_function = fn(pid, binary) -> send(pid, {:binary, binary}); :ok end
    input = %DetailedMessage{
      timestamp: 72,
      stream_id: 55,
      content: %VideoData{data: <<152::12 * 8>>}
    }

    assert {:ok, handler} = ProtocolHandler.start_link("id", self(), socket_function)
    assert :ok = ProtocolHandler.set_session(handler, self(), fn(_, _) -> :ok end)
    assert :ok = ProtocolHandler.send_message(handler, input)

    expected_binary = <<0::2, 21::6, 72::size(3)-unit(8), 12::size(3)-unit(8), 9::8, 55::size(4)-unit(8)-little, 152::size(12)-unit(8)>>
    assert_receive {:binary, ^expected_binary}
  end

end