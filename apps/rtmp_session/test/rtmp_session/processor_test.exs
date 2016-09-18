defmodule RtmpSession.ProcessorTest do
  use ExUnit.Case, async: true
  use ListAssertions

  alias RtmpSession.DetailedMessage, as: DetailedMessage
  alias RtmpSession.Processor, as: RtmpProcessor
  alias RtmpSession.Events, as: Events
  alias RtmpSession.SessionConfig, as: SessionConfig

  require Logger

  defmodule TestContext do
    defstruct processor: nil,
      application_name: nil,
      active_stream_id: nil
  end

  test "Can handle peer chunk size message" do
    alias RtmpSession.Messages.SetChunkSize, as: SetChunkSize

    processor = RtmpProcessor.new(%SessionConfig{})
    message = %DetailedMessage{content: %SetChunkSize{size: 4096}}
    {_, results} = RtmpProcessor.handle(processor, message)

    assert_contains(results, {:event, %Events.PeerChunkSizeChanged{new_chunk_size: 4096}})
  end

  test "Can handle peer window ack size and sends acknowledgement when received enough bytes" do
    alias RtmpSession.Messages.WindowAcknowledgementSize, as: WindowAcknowledgementSize
    alias RtmpSession.Messages.Acknowledgement, as: Acknowledgement

    processor = RtmpProcessor.new(%SessionConfig{})
    message = %DetailedMessage{content: %WindowAcknowledgementSize{size: 500}}
    {processor, results1} = RtmpProcessor.handle(processor, message)
    {_, results2} = RtmpProcessor.notify_bytes_received(processor, 800)

    assert([] = results1)
    assert_contains(results2, {:response, %DetailedMessage{
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
        command_object: %{"app" => "some_app"},
        additional_values: []
      }
    }

    # Connect command received
    {processor, connect_results} = RtmpProcessor.handle(processor, command)

    assert_contains(connect_results, {:response, %DetailedMessage{
      stream_id: 0,
      content: %SetPeerBandwidth{window_size: 6000, limit_type: :hard}
    }})

    assert_contains(connect_results, {:response, %DetailedMessage{
      stream_id: 0,
      content: %WindowAcknowledgementSize{size: 7000}
    }})

    assert_contains(connect_results, {:response, %DetailedMessage{
      stream_id: 0,
      content: %SetChunkSize{size: 5000}
    }})

    assert_contains(connect_results, {:response, %DetailedMessage{
      stream_id: 0,
      content: %UserControl{type: :stream_begin, stream_id: 0}
    }})

    {:event, event} = assert_contains(connect_results, {:event, %Events.ConnectionRequested{
      request_id: _,
      app_name: "some_app"
    }})

    # Accept connection request
    {_, accept_results} = RtmpProcessor.accept_request(processor, event.request_id)

    assert_contains(accept_results, {:response, %DetailedMessage{
      stream_id: 0,
      content: %Amf0Command{
        command_name: "_result",
        transaction_id: 1,
        command_object: %{
          "fmsVer" => "version",
          "capabilities" => 31
        },
        additional_values: [%{
          "level" => "status",
          "code" => "NetConnection.Connect.Success",
          "description" => "Connection succeeded",
          "objectEncoding" => 0
        }]
      }
    }})
  end

  test "Can create stream on connected session" do
    alias RtmpSession.Messages.Amf0Command, as: Amf0Command

    %TestContext{processor: processor} = get_connected_processor()
    
    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Amf0Command{
        command_name: "createStream",
        transaction_id: 4,
        command_object: nil,
        additional_values: []
      }
    }

    {_, create_stream_results} = RtmpProcessor.handle(processor, command)
    {:response, response} = assert_contains(create_stream_results, 
      {:response, %DetailedMessage{
        stream_id: 0,
        content: %Amf0Command{
          command_name: "_result",
          transaction_id: 4,
          command_object: nil
        }
      }}      
    )

    [stream_id] = response.content.additional_values
    assert is_number(stream_id)
  end 

  test "Can accept live publishing to requested stream key" do
    alias RtmpSession.Messages.Amf0Command, as: Amf0Command

    %TestContext{
      processor: processor,
      active_stream_id: active_stream_id,
      application_name: app_name
    } = get_connected_processor_with_active_stream()

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: active_stream_id,
      content: %Amf0Command{
        command_name: "publish",
        transaction_id: 0,
        command_object: nil,
        additional_values: ["stream_key", "live"]
      }
    }

    {processor, pub_results} = RtmpProcessor.handle(processor, command)
    {:event, event} = assert_contains(pub_results, 
      {:event, %Events.PublishStreamRequested{
        app_name: ^app_name,
        stream_key: "stream_key"
      }}
    )

    {_, accept_results} = RtmpProcessor.accept_request(processor, event.request_id)
    assert_contains(accept_results,
      {:response, %DetailedMessage{
        stream_id: ^active_stream_id,
        content: %Amf0Command{
          command_name: "onStatus",
          transaction_id: 0,
          command_object: nil,
          additional_values: [%{
            "level" => "status",
            "code" => "NetStream.Publish.Start",
            "description" => _
          }]
        }
      }} 
    )
  end

  defp get_connected_processor do
    alias RtmpSession.Messages.Amf0Command, as: Amf0Command

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Amf0Command{
        command_name: "connect",
        transaction_id: 1,
        command_object: %{"app" => "some_app"}
      }
    }

    processor = RtmpProcessor.new(%SessionConfig{})
    {processor, connect_results} = RtmpProcessor.handle(processor, command)
    {:event, event} = assert_contains(connect_results, {:event, %Events.ConnectionRequested{app_name: "some_app"}})

    {processor, _} = RtmpProcessor.accept_request(processor, event.request_id)

    %TestContext{
      processor: processor,
      application_name: event.app_name
    }
  end

  defp get_connected_processor_with_active_stream do
    alias RtmpSession.Messages.Amf0Command, as: Amf0Command

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Amf0Command{
        command_name: "connect",
        transaction_id: 1,
        command_object: %{"app" => "some_app"}
      }
    }

    processor = RtmpProcessor.new(%SessionConfig{})
    {processor, connect_results} = RtmpProcessor.handle(processor, command)
    {:event, event} = assert_contains(connect_results, {:event, %Events.ConnectionRequested{}})

    {processor, _} = RtmpProcessor.accept_request(processor, event.request_id)

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Amf0Command{
        command_name: "createStream",
        transaction_id: 4,
        command_object: nil,
        additional_values: []
      }
    }

    {processor, create_stream_results} = RtmpProcessor.handle(processor, command)
    {:response, response} = assert_contains(create_stream_results, 
      {:response, %DetailedMessage{content: %Amf0Command{command_name: "_result", transaction_id: 4}}}      
    )

    [stream_id] = response.content.additional_values

    %TestContext{
      processor: processor,
      application_name: event.app_name,
      active_stream_id: stream_id
    }
  end
  
end