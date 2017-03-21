defmodule Rtmp.Protocol.HandlerTest do
  use ExUnit.Case, async: false
  require Logger

  alias Rtmp.Protocol.Handler, as: ProtocolHandler
  alias Rtmp.Protocol.DetailedMessage, as: DetailedMessage
  alias Rtmp.Protocol.Messages.VideoData, as: VideoData
  alias Rtmp.Protocol.Messages.AudioData, as: AudioData
  alias Rtmp.Protocol.Messages.SetChunkSize, as: SetChunkSize

  def send_data(pid, data, packet_type) do
    _ = send(pid, {:binary, data, packet_type})
    :ok
  end

  def handle_rtmp_input(pid, message) do
    _ = send(pid, {:message, message})
    :ok
  end

  def notify_byte_count(pid, in_or_out, count) do
    _ = send(pid, {in_or_out, count})
    :ok
  end

  test "Valid chunk 0 RTMP binary input deserialized and sent via session function" do
    input = <<0::2, 50::6, 72::size(3)-unit(8), 12::size(3)-unit(8), 9::8, 55::size(4)-unit(8)-little, 152::size(12)-unit(8)>>

    assert {:ok, handler} = ProtocolHandler.start_link("id", self(), __MODULE__)
    assert :ok = ProtocolHandler.set_session(handler, self(), __MODULE__)
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
    input1 = <<0::2, 50::6, 72::size(3)-unit(8), 12::size(3)-unit(8), 9::8, 55::size(4)-unit(8)-little, 152::size(12)-unit(8)>>
    input2 = <<1::2, 50::6, 10::size(3)-unit(8), 12::size(3)-unit(8), 9::8, 122::size(12)-unit(8)>>

    assert {:ok, handler} = ProtocolHandler.start_link("id", self(), __MODULE__)
    assert :ok = ProtocolHandler.set_session(handler, self(), __MODULE__)
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
    input1 = <<0::2, 50::6, 72::size(3)-unit(8), 138::size(3)-unit(8), 9::8, 55::size(4)-unit(8)-little, 0::size(128)-unit(8)>>
    input2 = <<3::2, 50::6, 122::size(10)-unit(8)>>

    assert {:ok, handler} = ProtocolHandler.start_link("id", self(), __MODULE__)
    assert :ok = ProtocolHandler.set_session(handler, self(), __MODULE__)
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
    input1 = <<0::2, 50::6, 72::size(3)-unit(8), 4::size(3)-unit(8), 1::8, 55::size(4)-unit(8)-little, 200::size(4)-unit(8)>>
    input2 = <<1::2, 50::6, 10::size(3)-unit(8), 200::size(3)-unit(8), 9::8, 122::size(200)-unit(8)>>

    assert {:ok, handler} = ProtocolHandler.start_link("id", self(), __MODULE__)
    assert :ok = ProtocolHandler.set_session(handler, self(), __MODULE__)
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

    assert {:ok, handler} = ProtocolHandler.start_link("id", self(), __MODULE__)
    assert :ok = ProtocolHandler.set_session(handler, self(), __MODULE__)
    assert :ok = ProtocolHandler.send_message(handler, input1)
    assert :ok = ProtocolHandler.send_message(handler, input2)

    expected_binary1 = <<0::2, 21::6, 72::size(3)-unit(8), 12::size(3)-unit(8), 9::8, 55::size(4)-unit(8)-little, 152::size(12)-unit(8)>>
    expected_binary2 = <<1::2, 21::6, 10::size(3)-unit(8), 13::size(3)-unit(8), 9::8, 122::size(13)-unit(8)>>

    assert_receive {:binary, ^expected_binary1, _}
    assert_receive {:binary, ^expected_binary2, _}
  end

  test "Passed in message is split if greater than max chunk size" do
    input1 = %DetailedMessage{
      timestamp: 72,
      stream_id: 55,
      content: %VideoData{data: <<122::138 * 8>>}
    }

    assert {:ok, handler} = ProtocolHandler.start_link("id", self(), __MODULE__)
    assert :ok = ProtocolHandler.set_session(handler, self(), __MODULE__)
    assert :ok = ProtocolHandler.send_message(handler, input1)

    expected_binary1 = <<0::2, 21::6, 72::size(3)-unit(8), 138::size(3)-unit(8), 9::8, 55::size(4)-unit(8)-little, 0::size(128)-unit(8)>>
    expected_binary2 = <<3::2, 21::6, 122::size(10)-unit(8)>>
    expected_binary = expected_binary1 <> expected_binary2

    assert_receive {:binary, ^expected_binary, _}
  end

  test "Sending a SetChunkSize message updates the chunk size for following chunks" do
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

    assert {:ok, handler} = ProtocolHandler.start_link("id", self(), __MODULE__)
    assert :ok = ProtocolHandler.set_session(handler, self(), __MODULE__)
    assert :ok = ProtocolHandler.send_message(handler, input1)
    assert :ok = ProtocolHandler.send_message(handler, input2)

    expected_binary1 = <<0::2, 2::6, 72::size(3)-unit(8), 4::size(3)-unit(8), 1::8, 55::size(4)-unit(8)-little, 200::size(4)-unit(8)>>
    expected_binary2 = <<0::2, 21::6, 82::size(3)-unit(8), 200::size(3)-unit(8), 9::8, 55::size(4)-unit(8)-little, 122::size(200)-unit(8)>>

    assert_receive {:binary, ^expected_binary1, _}
    assert_receive {:binary, ^expected_binary2, _}
  end

  test "Can read multiple chunks in a single packet" do
    input1 = <<0::2, 50::6, 72::size(3)-unit(8), 12::size(3)-unit(8), 9::8, 55::size(4)-unit(8)-little, 152::size(12)-unit(8)>>
    input2 = <<1::2, 50::6, 10::size(3)-unit(8), 12::size(3)-unit(8), 9::8, 122::size(12)-unit(8)>>

    assert {:ok, handler} = ProtocolHandler.start_link("id", self(), __MODULE__)
    assert :ok = ProtocolHandler.set_session(handler, self(), __MODULE__)
    assert :ok = ProtocolHandler.notify_input(handler, input1 <> input2)

    assert_receive {:message, %DetailedMessage{
      timestamp: 72,
      stream_id: 55,
      content: %VideoData{
        data: <<152::12 * 8>>
      }
    }}

    assert_receive {:message, %DetailedMessage{
      timestamp: 82,
      stream_id: 55,
      content: %VideoData{
        data: <<122::12 * 8>>
      }
    }}
  end

  test "Announces total bytes received after processing input" do
    input1 = <<0::2, 50::6, 72::size(3)-unit(8), 12::size(3)-unit(8), 9::8, 55::size(4)-unit(8)-little, 152::size(12)-unit(8)>>
    input2 = <<1::2, 50::6, 10::size(3)-unit(8), 12::size(3)-unit(8), 9::8, 122::size(12)-unit(8)>>

    assert {:ok, handler} = ProtocolHandler.start_link("id", self(), __MODULE__)
    assert :ok = ProtocolHandler.set_session(handler, self(), __MODULE__)
    assert :ok = ProtocolHandler.notify_input(handler, input1)
    assert :ok = ProtocolHandler.notify_input(handler, input2)

    expected_receive_count = byte_size(input1 <> input2)
    assert_receive {:bytes_received, ^expected_receive_count}, 1000
  end

  test "Announces total bytes sent after sending bytes to socket handler" do
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

    assert {:ok, handler} = ProtocolHandler.start_link("id", self(), __MODULE__)
    assert :ok = ProtocolHandler.set_session(handler, self(), __MODULE__)
    assert :ok = ProtocolHandler.send_message(handler, input1)
    assert :ok = ProtocolHandler.send_message(handler, input2)

    expected_binary1 = <<0::2, 2::6, 72::size(3)-unit(8), 4::size(3)-unit(8), 1::8, 55::size(4)-unit(8)-little, 200::size(4)-unit(8)>>
    expected_binary2 = <<0::2, 21::6, 82::size(3)-unit(8), 200::size(3)-unit(8), 9::8, 55::size(4)-unit(8)-little, 122::size(200)-unit(8)>>
    expected_sent_size = byte_size(expected_binary1 <> expected_binary2)

    assert_receive {:bytes_sent, ^expected_sent_size}, 1000
  end

  test "Video packets passed to socket handler are flagged as video packet type" do
    input = %DetailedMessage{
      timestamp: 72,
      stream_id: 55,
      content: %VideoData{data: <<5::200>>}
    }

    assert {:ok, handler} = ProtocolHandler.start_link("id", self(), __MODULE__)
    assert :ok = ProtocolHandler.set_session(handler, self(), __MODULE__)
    assert :ok = ProtocolHandler.send_message(handler, input)

    assert_receive {:binary, _, :video}
  end

  test "Audio packets passed to socket handler are flagged as audio packet type" do
    input = %DetailedMessage{
      timestamp: 72,
      stream_id: 55,
      content: %AudioData{data: <<6::200>>}
    }

    assert {:ok, handler} = ProtocolHandler.start_link("id", self(), __MODULE__)
    assert :ok = ProtocolHandler.set_session(handler, self(), __MODULE__)
    assert :ok = ProtocolHandler.send_message(handler, input)

    assert_receive {:binary, _, :audio}
  end

  test "Misc rtmp messages are passed to socket handler are flagged as misc packet type" do
    input = %DetailedMessage{
      timestamp: 72,
      stream_id: 55,
      content: %SetChunkSize{size: 200}
    }

    assert {:ok, handler} = ProtocolHandler.start_link("id", self(), __MODULE__)
    assert :ok = ProtocolHandler.set_session(handler, self(), __MODULE__)
    assert :ok = ProtocolHandler.send_message(handler, input)

    assert_receive {:binary, _, :misc}
  end
end