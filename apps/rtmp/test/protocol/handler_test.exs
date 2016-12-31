defmodule Rtmp.Protocol.HandlerTest do
  use ExUnit.Case, async: true
  require Logger

  alias Rtmp.Protocol.Handler, as: ProtocolHandler
  alias Rtmp.Protocol.DetailedMessage, as: DetailedMessage
  alias Rtmp.Protocol.Messages.VideoData, as: VideoData
  alias Rtmp.Protocol.Messages.SetChunkSize, as: SetChunkSize

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
    }}
  end

  test "Can deserialize compressed (type 2) binary imput" do
    session_function = fn(pid, message) -> send(pid, {:message, message}); :ok end
    input1 = <<0::2, 50::6, 72::size(3)-unit(8), 12::size(3)-unit(8), 9::8, 55::size(4)-unit(8)-little, 152::size(12)-unit(8)>>
    input2 = <<1::2, 50::6, 10::size(3)-unit(8), 12::size(3)-unit(8), 9::8, 122::size(12)-unit(8)>>

    assert {:ok, handler} = ProtocolHandler.start_link("id", nil, nil)
    assert :ok = ProtocolHandler.set_session(handler, self(), session_function)
    assert :ok = ProtocolHandler.notify_input(handler, input1)
    assert :ok = ProtocolHandler.notify_input(handler, input2)

    assert_receive {:message, %DetailedMessage{
      timestamp: 82,
      stream_id: 55,
      content: %VideoData{
        data: <<122::12 * 8>>
      }
    }}
  end

  test "Split chunks are read and passed on properly" do
    session_function = fn(pid, message) -> send(pid, {:message, message}); :ok end
    input1 = <<0::2, 50::6, 72::size(3)-unit(8), 138::size(3)-unit(8), 9::8, 55::size(4)-unit(8)-little, 0::size(128)-unit(8)>>
    input2 = <<3::2, 50::6, 122::size(10)-unit(8)>>

    assert {:ok, handler} = ProtocolHandler.start_link("id", nil, nil)
    assert :ok = ProtocolHandler.set_session(handler, self(), session_function)
    assert :ok = ProtocolHandler.notify_input(handler, input1)
    assert :ok = ProtocolHandler.notify_input(handler, input2)

    assert_receive {:message, %DetailedMessage{
      timestamp: 72,
      stream_id: 55,
      content: %VideoData{
        data: <<122::138 * 8>>
      }
    }}
  end

  test "Automatically adjusts to SetChunkSize messages" do
    session_function = fn(pid, message) -> send(pid, {:message, message}); :ok end
    input1 = <<0::2, 50::6, 72::size(3)-unit(8), 4::size(3)-unit(8), 1::8, 55::size(4)-unit(8)-little, 200::size(4)-unit(8)>>
    input2 = <<1::2, 50::6, 10::size(3)-unit(8), 200::size(3)-unit(8), 9::8, 122::size(200)-unit(8)>>

    assert {:ok, handler} = ProtocolHandler.start_link("id", nil, nil)
    assert :ok = ProtocolHandler.set_session(handler, self(), session_function)
    assert :ok = ProtocolHandler.notify_input(handler, input1)
    assert :ok = ProtocolHandler.notify_input(handler, input2)

    assert_receive {:message, %DetailedMessage{
      timestamp: 82,
      stream_id: 55,
      content: %VideoData{
        data: <<122::200 * 8>>
      }
    }}
  end

  test "Passed in messages are serialized (with compression) and sent to socket function" do
    socket_function = fn(pid, binary) -> send(pid, {:binary, binary}); :ok end
    input1 = %DetailedMessage{
      timestamp: 72,
      stream_id: 55,
      content: %VideoData{data: <<152::12 * 8>>}
    }

    input2 = %DetailedMessage{
      timestamp: 82,
      stream_id: 55,
      content: %VideoData{
        data: <<122::13 * 8>>
      }
    }

    assert {:ok, handler} = ProtocolHandler.start_link("id", self(), socket_function)
    assert :ok = ProtocolHandler.set_session(handler, self(), fn(_, _) -> :ok end)
    assert :ok = ProtocolHandler.send_message(handler, input1)
    assert :ok = ProtocolHandler.send_message(handler, input2)

    expected_binary1 = <<0::2, 21::6, 72::size(3)-unit(8), 12::size(3)-unit(8), 9::8, 55::size(4)-unit(8)-little, 152::size(12)-unit(8)>>
    expected_binary2 = <<1::2, 21::6, 10::size(3)-unit(8), 13::size(3)-unit(8), 9::8, 122::size(13)-unit(8)>>

    assert_receive {:binary, ^expected_binary1}
    assert_receive {:binary, ^expected_binary2}
  end

  test "Passed in message is split if greater than max chunk size" do
    socket_function = fn(pid, binary) -> send(pid, {:binary, binary}); :ok end
    input1 = %DetailedMessage{
      timestamp: 72,
      stream_id: 55,
      content: %VideoData{data: <<122::138 * 8>>}
    }
    assert {:ok, handler} = ProtocolHandler.start_link("id", self(), socket_function)
    assert :ok = ProtocolHandler.set_session(handler, self(), fn(_, _) -> :ok end)
    assert :ok = ProtocolHandler.send_message(handler, input1)

    expected_binary1 = <<0::2, 21::6, 72::size(3)-unit(8), 138::size(3)-unit(8), 9::8, 55::size(4)-unit(8)-little, 0::size(128)-unit(8)>>
    expected_binary2 = <<3::2, 21::6, 122::size(10)-unit(8)>>
    expected_binary = expected_binary1 <> expected_binary2

    assert_receive {:binary, ^expected_binary}
  end

  test "Sending a SetChunkSize message updates the chunk size for following chunks" do
    socket_function = fn(pid, binary) -> send(pid, {:binary, binary}); :ok end

    input1 = %DetailedMessage{
      timestamp: 72,
      stream_id: 55,
      content: %SetChunkSize{size: 200}
    }

    input2 = %DetailedMessage{
      timestamp: 82,
      stream_id: 55,
      content: %VideoData{
        data: <<122::200 * 8>>
      }
    }

    assert {:ok, handler} = ProtocolHandler.start_link("id", self(), socket_function)
    assert :ok = ProtocolHandler.set_session(handler, self(), fn(_, _) -> :ok end)
    assert :ok = ProtocolHandler.send_message(handler, input1)
    assert :ok = ProtocolHandler.send_message(handler, input2)

    expected_binary1 = <<0::2, 2::6, 72::size(3)-unit(8), 4::size(3)-unit(8), 1::8, 55::size(4)-unit(8)-little, 200::size(4)-unit(8)>>
    expected_binary2 = <<0::2, 21::6, 82::size(3)-unit(8), 200::size(3)-unit(8), 9::8, 55::size(4)-unit(8)-little, 122::size(200)-unit(8)>>

    assert_receive {:binary, ^expected_binary1}
    assert_receive {:binary, ^expected_binary2}

  end

end