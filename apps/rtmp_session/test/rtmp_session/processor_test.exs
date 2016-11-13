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
      active_stream_id: nil,
      stream_key: nil
  end

  test "Can handle peer chunk size message" do
    alias RtmpSession.Messages.SetChunkSize, as: SetChunkSize

    processor = RtmpProcessor.new(%SessionConfig{}, "abc")
    message = %DetailedMessage{content: %SetChunkSize{size: 4096}}
    {_, results} = RtmpProcessor.handle(processor, message)

    assert_contains(results, {:event, %Events.PeerChunkSizeChanged{new_chunk_size: 4096}})
  end

  test "Can handle peer window ack size and sends acknowledgement when received enough bytes" do
    alias RtmpSession.Messages.WindowAcknowledgementSize, as: WindowAcknowledgementSize
    alias RtmpSession.Messages.Acknowledgement, as: Acknowledgement

    processor = RtmpProcessor.new(%SessionConfig{}, "abc")
    :timer.sleep(100)

    message = %DetailedMessage{content: %WindowAcknowledgementSize{size: 500}}
    {processor, results1} = RtmpProcessor.handle(processor, message)
    {_, results2} = RtmpProcessor.notify_bytes_received(processor, 800)

    assert([] = results1)
    assert_contains(results2, {:response, %DetailedMessage{
      timestamp: timestamp,
      content: %Acknowledgement{sequence_number: 800}
    }} when timestamp > 0)
  end

  test "Can accept connection request and provide valid responses" do
    alias RtmpSession.Messages.WindowAcknowledgementSize, as: WindowAcknowledgementSize
    alias RtmpSession.Messages.Amf0Command, as: Amf0Command
    alias RtmpSession.Messages.SetPeerBandwidth, as: SetPeerBandwidth
    alias RtmpSession.Messages.UserControl, as: UserControl

    config = %SessionConfig{
      fms_version: "version",
      chunk_size: 5000,
      peer_bandwidth: 6000,
      window_ack_size: 7000
    }

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

    processor = RtmpProcessor.new(config, "abc")
    :timer.sleep(100)

    # Connect command received
    {processor, connect_results} = RtmpProcessor.handle(processor, command)

    assert_contains(connect_results, {:response, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %SetPeerBandwidth{window_size: 6000, limit_type: :dynamic},
      force_uncompressed: true
    }} when timestamp > 0)

    assert_contains(connect_results, {:response, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %WindowAcknowledgementSize{size: 7000},
      force_uncompressed: true
    }} when timestamp > 0)

    assert_contains(connect_results, {:response, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %UserControl{type: :stream_begin, stream_id: 0},
      force_uncompressed: true
    }} when timestamp > 0)

    {:event, event} = assert_contains(connect_results, {:event, %Events.ConnectionRequested{
      request_id: _,
      app_name: "some_app"
    }})

    # Accept connection request
    {_, accept_results} = RtmpProcessor.accept_request(processor, event.request_id)

    assert_contains(accept_results, {:response, 
      %DetailedMessage{
        stream_id: 0,
        timestamp: timestamp,
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
      }} when timestamp > 0
    )
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
        timestamp: timestamp,
        content: %Amf0Command{
          command_name: "_result",
          transaction_id: 4,
          command_object: nil
        }
      }} when timestamp > 0
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
        timestamp: timestamp,
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
      }} when timestamp > 0 
    )
  end

  test "Can receive and raise event for metadata from OBS" do
    alias RtmpSession.Messages.Amf0Data, as: Amf0Data
    alias RtmpSession.StreamMetadata, as: StreamMetadata

    %TestContext{
      processor: processor,
      application_name: application_name,
      active_stream_id: stream_id,
      stream_key: stream_key
    } = get_publishing_processor()

    message = %DetailedMessage{
      timestamp: 0,
      stream_id: stream_id,
      content: %Amf0Data{parameters: [
        "@setDataFrame",
        "onMetaData",
        %{
          "width" => 1920,
          "height" => 1080,
          "videocodecid" => "avc1",
          "videodatarate" => 1200,
          "framerate" => 30,
          "audiocodecid" => "mp4a",
          "audiodatarate" => 96,
          "audiosamplerate" => 48000,
          "audiosamplesize" => 16,
          "audiochannels" => 2,
          "stereo" => true,
          "encoder" => "Test Encoder"
        }
      ]}
    }

    {_, results} = RtmpProcessor.handle(processor, message)

    assert_contains(results, {:event, %Events.StreamMetaDataChanged{
      app_name: ^application_name,
      stream_key: ^stream_key,
      meta_data: %StreamMetadata{
        video_width: 1920,
        video_height: 1080,
        video_codec: "avc1",
        video_frame_rate: 30,
        video_bitrate_kbps: 1200,
        audio_codec: "mp4a",
        audio_bitrate_kbps: 96,
        audio_sample_rate: 48000,
        audio_channels: 2,
        audio_is_stereo: true,
        encoder: "Test Encoder"
      }
    }})
  end

  test "Can receive audio data on published stream" do
    alias RtmpSession.Messages.AudioData, as: AudioData

    %TestContext{
      processor: processor,
      application_name: application_name,
      active_stream_id: stream_id,
      stream_key: stream_key
    } = get_publishing_processor()

    message = %DetailedMessage{
      timestamp: 0,
      stream_id: stream_id,
      content: %AudioData{data: <<1,2,3>>}
    }

    {_, results} = RtmpProcessor.handle(processor, message)

    assert_contains(results, {:event, %Events.AudioVideoDataReceived{
      app_name: ^application_name,
      stream_key: ^stream_key,
      data_type: :audio,
      data: <<1,2,3>>
    }})
  end

  test "Can receive video data on published stream" do
    alias RtmpSession.Messages.VideoData, as: VideoData

    %TestContext{
      processor: processor,
      application_name: application_name,
      active_stream_id: stream_id,
      stream_key: stream_key
    } = get_publishing_processor()

    message = %DetailedMessage{
      timestamp: 0,
      stream_id: stream_id,
      content: %VideoData{data: <<1,2,3>>}
    }

    {_, results} = RtmpProcessor.handle(processor, message)

    assert_contains(results, {:event, %Events.AudioVideoDataReceived{
      app_name: ^application_name,
      stream_key: ^stream_key,
      data_type: :video,
      data: <<1,2,3>>
    }})
  end

  test "Accepting connection request responds with chunk size" do
    alias RtmpSession.Messages.Amf0Command, as: Amf0Command
    alias RtmpSession.Messages.SetChunkSize, as: SetChunkSize

    chunk_size = 1024

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Amf0Command{
        command_name: "connect",
        transaction_id: 1,
        command_object: %{"app" => "some_app"}
      }
    }

    processor = RtmpProcessor.new(%SessionConfig{chunk_size: chunk_size}, "abc")
    
    # Make sure some time has passed since creating the processor
    #   to allow for non-zero timestamp checking
    :timer.sleep(200) 

    {processor, connect_results} = RtmpProcessor.handle(processor, command)
    {:event, event} = assert_contains(connect_results, {:event, %Events.ConnectionRequested{app_name: "some_app"}})

    {_, accept_results} = RtmpProcessor.accept_request(processor, event.request_id)
    assert_contains(accept_results, {:response, 
      %DetailedMessage{
        stream_id: 0,
        timestamp: timestamp,
        content: %SetChunkSize{size: ^chunk_size}
      }} when timestamp > 0
    )
  end

  test "Publish finished event raised when deleteStream invoked on publishing stream id" do
    alias RtmpSession.Messages.Amf0Command, as: Amf0Command

    %TestContext{
      processor: processor,
      application_name: application_name,
      active_stream_id: stream_id,
      stream_key: stream_key
    } = get_publishing_processor()

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Amf0Command{
        command_name: "deleteStream",
        transaction_id: 8,
        command_object: nil,
        additional_values: [stream_id]
      }
    }

    {_, results} = RtmpProcessor.handle(processor, command)

    assert_contains(results, {:event, %Events.PublishingFinished{
      app_name: ^application_name,
      stream_key: ^stream_key
    }})
  end

  test "Connect request strips trailing slash" do
    alias RtmpSession.Messages.Amf0Command, as: Amf0Command

    config = %SessionConfig{
      fms_version: "version",
      chunk_size: 5000,
      peer_bandwidth: 6000,
      window_ack_size: 7000
    }

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Amf0Command{
        command_name: "connect",
        transaction_id: 1,
        command_object: %{"app" => "some_app/"},
        additional_values: []
      }
    }

    processor = RtmpProcessor.new(config, "abc")
    :timer.sleep(100)

    {_, connect_results} = RtmpProcessor.handle(processor, command)

    {:event, _} = assert_contains(connect_results, {:event, %Events.ConnectionRequested{
      request_id: _,
      app_name: "some_app"
    }})
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

    processor = RtmpProcessor.new(%SessionConfig{}, "abc")
    
    # Make sure some time has passed since creating the processor
    #   to allow for non-zero timestamp checking
    :timer.sleep(200) 

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

    %TestContext{
      processor: processor,
      application_name: application_name
    } = get_connected_processor()

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
      application_name: application_name,
      active_stream_id: stream_id
    }
  end

  defp get_publishing_processor do
    alias RtmpSession.Messages.Amf0Command, as: Amf0Command

    %TestContext{
      processor: processor,
      application_name: application_name,
      active_stream_id: stream_id
    } = get_connected_processor_with_active_stream()

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: stream_id,
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
        app_name: ^application_name,
        stream_key: "stream_key"
      }}
    )

    {processor, _} = RtmpProcessor.accept_request(processor, event.request_id)

    %TestContext{
      processor: processor,
      application_name: application_name,
      active_stream_id: stream_id,
      stream_key: "stream_key"
    }
  end
  
end