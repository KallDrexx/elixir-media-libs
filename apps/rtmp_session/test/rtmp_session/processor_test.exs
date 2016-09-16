defmodule RtmpSession.ProcessorTest do
  use ExUnit.Case, async: true
  use ListAssertions

  alias RtmpSession.DetailedMessage, as: DetailedMessage
  alias RtmpSession.Processor, as: RtmpProcessor
  alias RtmpSession.Events, as: Events
  alias RtmpSession.SessionConfig, as: SessionConfig

  test "Can handle peer chunk size message" do
    alias RtmpSession.Messages.SetChunkSize, as: SetChunkSize

    processor = RtmpProcessor.new(%SessionConfig{})
    message = %DetailedMessage{content: %SetChunkSize{size: 4096}}
    {_, results} = RtmpProcessor.handle(processor, message)

    assert_list_contains(results, {:event, %Events.PeerChunkSizeChanged{new_chunk_size: 4096}})
  end

  test "Can handle peer window ack size and sends acknowledgement when received enough bytes" do
    alias RtmpSession.Messages.WindowAcknowledgementSize, as: WindowAcknowledgementSize
    alias RtmpSession.Messages.Acknowledgement, as: Acknowledgement

    processor = RtmpProcessor.new(%SessionConfig{})
    message = %DetailedMessage{content: %WindowAcknowledgementSize{size: 500}}
    {processor, results1} = RtmpProcessor.handle(processor, message)
    {_, results2} = RtmpProcessor.notify_bytes_received(processor, 800)

    assert([] = results1)
    assert_list_contains(results2, {:response, %DetailedMessage{
      content: %Acknowledgement{sequence_number: 800}
    }})
  end

  test "Can accept connection request and provide valid responses" do
    alias RtmpSession.Messages.WindowAcknowledgementSize, as: WindowAcknowledgementSize
    alias RtmpSession.Messages.Amf0Command, as: Amf0Command
    alias RtmpSession.Messages.SetPeerBandwidth, as: SetPeerBandwidth
    alias RtmpSession.Messages.SetChunkSize, as: SetChunkSize
    alias RtmpSession.Messages.UserControl, as: UserControl

    config = %SessionConfig{
      fms_version: "version",
      chunk_size: 5000,
      peer_bandwidth: 6000,
      window_ack_size: 7000
    }

    processor = RtmpProcessor.new(config)
    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Amf0Command{
        command_name: "connect",
        transaction_id: 1,
        command_object: %{
          "app": "some_app",
          "type": "nonprivate",
          "flashVer": "fver",
          "swfUrl": "rtmp://127.0.0.1/live",
          "tcUrl": "rtmp://127.0.0.2/live"
        },
        additional_values: []
      }
    }

    {processor, connect_results} = RtmpProcessor.handle(processor, command)

    assert_list_contains(connect_results, {:response, %DetailedMessage{
      stream_id: 0,
      content: %SetPeerBandwidth{window_size: 6000, limit_type: :hard}
    }})

    assert_list_contains(connect_results, {:response, %DetailedMessage{
      stream_id: 0,
      content: %WindowAcknowledgementSize{size: 7000}
    }})

    assert_list_contains(connect_results, {:response, %DetailedMessage{
      stream_id: 0,
      content: %SetChunkSize{size: 5000}
    }})

    assert_list_contains(connect_results, {:response, %DetailedMessage{
      stream_id: 0,
      content: %UserControl{type: :stream_begin, stream_id: 0}
    }})

    {:event, event} = assert_list_contains(connect_results, {:event, %Events.ConnectionRequested{
      request_id: _,
      app_name: "some_app"
    }})

    {processor, accept_results} = RtmpProcessor.accept_request(event.request_id)

    assert_list_contains(connect_results, {:response, %DetailedMessage{
      stream_id: 0,
      content: %Amf0Command{
        command_name: "_result",
        transaction_id: 1,
        command_object: %{
          "fmsVer": "version",
          "capabilities": 31
        },
        additional_values: [%{
          "level": "status",
          "code": "NetConnection.Connect.Success",
          "description": "Connection succeeded",
          "objectEncoding": 0
        }]
      }
    }})

  end
end