defmodule Rtmp.ClientSession.HandlerTest do
  use ExUnit.Case, async: true

  alias Rtmp.ClientSession.Configuration, as: Configuration
  alias Rtmp.ClientSession.Handler, as: Handler
  alias Rtmp.ClientSession.Events, as: Events
  alias Rtmp.Protocol.DetailedMessage, as: DetailedMessage
  alias Rtmp.Protocol.Messages, as: Messages

  defmodule TestContext do
    defstruct session: nil,
              app_name: nil,
              active_stream_id: nil,
              stream_key: nil,
              options: nil
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

  test "Can send connection request and raise accept response", context do
    session = context[:session]
    options = context[:options]

    :timer.sleep(100) # To verify non_zero timestamps in responses

    assert :ok == Handler.request_connection(session, "my_app")

    expected_flash_ver = options.flash_version
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

    result = %DetailedMessage{
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

    assert :ok == Handler.handle_rtmp_input(session, result)
    assert_receive {:event, %Events.ConnectionResponseReceived{
      was_accepted: true,
      response_text: "success123"
    }}

  end
end