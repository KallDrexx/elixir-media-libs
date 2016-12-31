defmodule Rtmp.ServerSession.HandlerTest do
  use ExUnit.Case, async: true

  alias Rtmp.ServerSession.Configuration, as: Configuration
  alias Rtmp.ServerSession.Handler, as: Handler
  alias Rtmp.ServerSession.Events, as: Events

  setup do
    output_handler = fn(pid, message) -> send(pid, {:message, message}); :ok end
    event_handler = fn(pid, event) -> send(pid, {:event, event}); :ok end

    connection_id = "test_connection"
    options = %Configuration{
      fms_version: "test version",
      chunk_size: 9999,
      peer_bandwidth: 8888,
      window_ack_size: 7777
    }

    {:ok, session} = Handler.start_link(connection_id, options)
    :ok = Handler.set_event_handler(session, self(), event_handler)
    :ok = Handler.set_rtmp_output_handler(session, self(), output_handler)

    [session: session, connection_id: connection_id, options: options]
  end

  test "Connection request automatically triggers sending initial responses", context do
    alias Rtmp.Protocol.DetailedMessage, as: DetailedMessage
    alias Rtmp.Protocol.Messages.Amf0Command, as: Amf0Command
    alias Rtmp.Protocol.Messages.WindowAcknowledgementSize, as: WindowAcknowledgmentSize
    alias Rtmp.Protocol.Messages.SetPeerBandwidth, as: SetPeerBandwidth
    alias Rtmp.Protocol.Messages.UserControl, as: UserControl

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Amf0Command{
        command_name: "connect",
        transaction_id: 1,
        command_object: %{"app" => "some_app"},
        additional_values: []
      }
    }

    expected_window_size = context[:options].window_ack_size
    expected_peer_bandwidth = context[:options].peer_bandwidth

    # To verify non_zero timestamps in responses
    :timer.sleep(100)

    session = context[:session]
    assert :ok = Handler.handle_rtmp_input(session, command)

    assert_receive {:message, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %WindowAcknowledgmentSize{size: ^expected_window_size},
      force_uncompressed: true
    }} when timestamp > 0

    assert_receive {:message, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %SetPeerBandwidth{window_size: ^expected_peer_bandwidth, limit_type: :dynamic},
      force_uncompressed: true
    }} when timestamp > 0

    assert_receive {:message, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %UserControl{type: :stream_begin, stream_id: 0},
      force_uncompressed: true
    }} when timestamp > 0

    assert_receive {:message, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %Amf0Command{
          command_name: "onBWDone",
          transaction_id: 0,
          command_object: nil,
          additional_values: [8192]
      },
    }} when timestamp > 0
  end

  test "Can accept connection request", context do
    alias Rtmp.Protocol.DetailedMessage, as: DetailedMessage
    alias Rtmp.Protocol.Messages.Amf0Command, as: Amf0Command

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Amf0Command{
        command_name: "connect",
        transaction_id: 1,
        command_object: %{"app" => "some_app"},
        additional_values: []
      }
    }

    expected_fms_version = context[:options].fms_version

    # To verify non_zero timestamps in responses
    :timer.sleep(100)

    session = context[:session]
    assert :ok = Handler.handle_rtmp_input(session, command)

    assert_receive {:event, %Events.ConnectionRequested{
      request_id: request_id,
      app_name: "some_app"
    }}

    assert :ok = Handler.accept_request(session, request_id)

    assert_receive{:message, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %Amf0Command{
        command_name: "_result",
        transaction_id: 1,
        command_object: %{
          "fmsVer" => ^expected_fms_version,
          "capabilities" => 31
        },
        additional_values: [%{
          "level" => "status",
          "code" => "NetConnection.Connect.Success",
          "description" => _,
          "objectEncoding" => 0
        }]
      }
    }} when timestamp > 0

  end
end