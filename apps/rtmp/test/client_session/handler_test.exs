defmodule Rtmp.ClientSession.HandlerTest do
  use ExUnit.Case, async: true

  alias Rtmp.ClientSession.Configuration, as: Configuration
  alias Rtmp.ClientSession.Handler, as: Handler
  alias Rtmp.ClientSession.Events, as: Events
  alias Rtmp.Protocol.DetailedMessage, as: DetailedMessage
  alias Rtmp.Protocol.Messages, as: Messages

  defmodule TestContext do
    defstruct session: nil,
              options: nil,
              app_name: nil
  end

  def send_event(pid, event) do
    _ = send(pid, {:event, event})
    :ok
  end

  def send_message(pid, message) do
    _ = send(pid, {:message, message})
    :ok
  end

  setup do
    connection_id = "test_connection"
    options = %Configuration{
      flash_version: "test version",
      window_ack_size: 7777,
      playback_buffer_length_ms: 1000
    }

    {:ok, session} = Handler.start_link(connection_id, options)
    :ok = Handler.set_event_handler(session, self(), __MODULE__)
    :ok = Handler.set_protocol_handler(session, self(), __MODULE__)

    [session: session, connection_id: connection_id, options: options]
  end

  test "Accepted connection request workflow", context do
    session = context[:session]
    options = context[:options]
    expected_flash_ver = options.flash_version
    expected_win_size = options.window_ack_size

    :timer.sleep(100) # To verify non_zero timestamps in responses

    assert :ok == Handler.request_connection(session, "my_app")   
    assert_receive {:message, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %Messages.Amf0Command{
        command_name: "connect",
        transaction_id: 1,
        command_object: %{
          "app" => "my_app",
          "flashVer" => ^expected_flash_ver,
          "objectEncoding" => 0
        },
        additional_values: []
      }
    }} when timestamp > 0

    command = %DetailedMessage{
      stream_id: 0,
      timestamp: 100,
      content: %Messages.Amf0Command{
        command_name: "_result",
        transaction_id: 1,
        command_object: %{
          "fmsVer" => "fms_ver",
          "capabilities" => 31
        },
        additional_values: [%{
          "level" => "status",
          "code" => "NetConnection.Connect.Success",
          "description" => "success123",
          "objectEncoding" => 0
        }]
      }
    }

    assert :ok == Handler.handle_rtmp_input(session, command)
    assert_receive {:event, %Events.ConnectionResponseReceived{
      was_accepted: true,
      response_text: "success123"
    }}

    # connection success should trigger ack size command
    assert_receive {:message, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %Messages.WindowAcknowledgementSize{size: ^expected_win_size}
    }} when timestamp > 0
  end

  test "Accepted playback request workflow", context do
    %TestContext{
      session: session,
      options: options
    } = get_connected_session(context)    

    stream_key = "abcdefg"
    created_stream_id = 5
    expected_buffer_length = options.playback_buffer_length_ms

    assert :ok == Handler.request_playback(session, stream_key)
    assert_receive {:message, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %Messages.Amf0Command{
        command_name: "createStream",
        transaction_id: create_stream_transaction_id,
        command_object: nil,
        additional_values: []
      }
    }} when timestamp > 0

    create_stream_response = %DetailedMessage{
      stream_id: 0,
      content: %Messages.Amf0Command{
        command_name: "_result",
        transaction_id: create_stream_transaction_id,
        command_object: nil,
        additional_values: [created_stream_id]
      }
    }

    assert :ok == Handler.handle_rtmp_input(session, create_stream_response)
    assert_receive {:message, %DetailedMessage{
      stream_id: 0,
      content: %Messages.UserControl{
        type: :set_buffer_length,
        stream_id: ^created_stream_id,
        buffer_length: ^expected_buffer_length
      }
    }}

    assert_receive {:message, %DetailedMessage{
      stream_id: ^created_stream_id,
      content: %Messages.Amf0Command{
        command_name: "play",
        command_object: nil,
        additional_values: [^stream_key]
      }
    }}

    description = "Started playing"
    start_command = %DetailedMessage{
      stream_id: created_stream_id,
      content: %Messages.Amf0Command{
        command_name: "onStatus",
        transaction_id: 0,
        command_object: nil,
        additional_values: [%{
          "level" => "status",
          "code" => "NetStream.Play.Start",
          "description" => description
        }]
      }
    }

    assert :ok == Handler.handle_rtmp_input(session, start_command)
    assert_receive {:event, %Events.PlayResponseReceived{
      was_accepted: true,
      response_text: ^description
    }}
  end

  defp get_connected_session(context) do
    :timer.sleep(10) # for non-zero timestamp checking

    test_context = %TestContext{
      session: context[:session],
      options: context[:options],
      app_name: "app_name"
    }

    expected_flash_ver = test_context.options.flash_version
    expected_app_name = test_context.app_name

    assert :ok == Handler.request_connection(test_context.session, test_context.app_name)
    assert_receive {:message, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %Messages.Amf0Command{
        command_name: "connect",
        transaction_id: 1,
        command_object: %{
          "app" => ^expected_app_name,
          "flashVer" => ^expected_flash_ver,
          "objectEncoding" => 0
        },
        additional_values: []
      }
    }} when timestamp > 0

    
    command = %DetailedMessage{
      stream_id: 0,
      timestamp: 100,
      content: %Messages.Amf0Command{
        command_name: "_result",
        transaction_id: 1,
        command_object: %{
          "fmsVer" => "fms_ver",
          "capabilities" => 31
        },
        additional_values: [%{
          "level" => "status",
          "code" => "NetConnection.Connect.Success",
          "description" => "success",
          "objectEncoding" => 0
        }]
      }
    }

    assert :ok == Handler.handle_rtmp_input(test_context.session, command) 
    assert_receive {:event, %Events.ConnectionResponseReceived{
      was_accepted: true
    }}

    test_context
  end
end