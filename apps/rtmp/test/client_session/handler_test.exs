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
              app_name: nil,
              stream_key: nil,
              active_stream_id: nil
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
    expected_win_size = options.window_ack_size

    :timer.sleep(20) # To verify non_zero timestamps in responses

    assert :ok == Handler.request_connection(session, "my_app")
    expect_connection_request_rtmp_message("my_app", options.flash_version)

    simulate_connect_response(session, true, "success123")
    expect_connection_response_received_event(true, "success123")

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

    assert :ok == Handler.request_playback(session, stream_key)

    transaction_id = expect_create_stream_rtmp_message()
    simulate_create_stream_response(session, transaction_id, created_stream_id)    
    expect_buffer_length_rtmp_message(created_stream_id, options.playback_buffer_length_ms)
    play_transaction_id = expect_play_rtmp_message(created_stream_id, stream_key)

    description = "Started playing"
    simulate_play_response(session, play_transaction_id, created_stream_id, true, description)
    expect_play_response_received_event(true, description)
  end

  test "Active playback raises events for stream metadata changes", context do
    %TestContext{
      session: session,
      stream_key: stream_key,
      active_stream_id: stream_id
    } = get_playback_session(context);

    simulated_metadata = %DetailedMessage{
      stream_id: stream_id,
      content: %Messages.Amf0Data{parameters: [
        'onMetaData',
        %{
          "height" => 720,
          "width" => 1280,
          "audiochannels" => 2,
          "audiocodecid" => "mp4a",
          "audiodatarate" => 96,
          "framerate" => 30,
          "videocodecid" => "avc1",
          "videodatarate" => 1000
        }
      ]}
    }

    assert :ok == Handler.handle_rtmp_input(session, simulated_metadata)
    assert_receive {:event, %Events.StreamMetaDataReceived{
      stream_key: ^stream_key,
      meta_data: %Rtmp.StreamMetadata{
        video_height: 720,
        video_width: 1280,
        video_codec: "avc1",
        video_frame_rate: 30,
        video_bitrate_kbps: 1000,
        audio_channels: 2,
        audio_codec: "mp4a",
        audio_bitrate_kbps: 96
      }
    }}
  end

  test "Active playback raises events for audio data received", context do
    %TestContext{
      session: session,
      stream_key: stream_key,
      active_stream_id: stream_id
    } = get_playback_session(context);

    simulated_audio_message = %DetailedMessage{
      timestamp: 512,
      stream_id: stream_id,
      content: %Messages.AudioData{data: <<100::12>>}
    }

    assert :ok == Handler.handle_rtmp_input(session, simulated_audio_message)
    assert_receive {:event, %Events.AudioVideoDataReceived{
      stream_key: ^stream_key,
      data_type: :audio,
      data: <<100::12>>,
      timestamp: 512,
      received_at_timestamp: received_at_timestamp,      
    }} when received_at_timestamp > 0
  end

  test "Active playback raises events for video data received", context do
    %TestContext{
      session: session,
      stream_key: stream_key,
      active_stream_id: stream_id
    } = get_playback_session(context);

    simulated_video_message = %DetailedMessage{
      timestamp: 512,
      stream_id: stream_id,
      content: %Messages.VideoData{data: <<100::12>>}
    }

    assert :ok == Handler.handle_rtmp_input(session, simulated_video_message)
    assert_receive {:event, %Events.AudioVideoDataReceived{
      stream_key: ^stream_key,
      data_type: :video,
      data: <<100::12>>,
      timestamp: 512,
      received_at_timestamp: received_at_timestamp,      
    }} when received_at_timestamp > 0
  end

  test "Can stop playback", context do
    %TestContext{
      session: session,
      stream_key: stream_key,
      active_stream_id: stream_id
    } = get_playback_session(context);

    assert :ok == Handler.stop_playback(session, stream_key)
    assert_receive {:message, %DetailedMessage{
      stream_id: ^stream_id,
      content: %Messages.Amf0Command{
        command_name: "closeStream",
        command_object: nil
      }
    }}
  end

  test "Accepted publishing request workflow", context do
    %TestContext{
      session: session,
    } = get_connected_session(context)

    stream_key = "abcdefg"
    created_stream_id = 5

    assert :ok == Handler.request_publish(session, stream_key, :live)
    transaction_id = expect_create_stream_rtmp_message()
    
    simulate_create_stream_response(session, transaction_id, created_stream_id)
    transaction_id = expect_publish_rtmp_message(created_stream_id, stream_key, "live")
    
    simulate_publish_response(session, transaction_id, created_stream_id, true, "success")
    expect_publish_response_received_event(stream_key, true, "success")
  end

  test "Active publisher can send stream metadata to server", context do
    %TestContext{
      session: session,
      stream_key: stream_key,
      active_stream_id: stream_id,
    } = get_publishing_session(context)

    metadata = %Rtmp.StreamMetadata{
      video_width: 100,
      video_height: 101,
      video_codec: "vc",
      video_frame_rate: 30,
      video_bitrate_kbps: 102,
      audio_codec: "ac",
      audio_bitrate_kbps: 103,
      audio_sample_rate: 104,
      audio_channels: 105,
      audio_is_stereo: true,
      encoder: "encoder",
    }

    assert :ok == Handler.publish_metadata(session, stream_key, metadata)
    assert_receive {:message, %DetailedMessage{
      stream_id: ^stream_id,
      timestamp: timestamp,
      content: %Messages.Amf0Data{
        parameters: [
          "@setDataFrame",
          "onMetaData",
          %{
            "width" => 100,
            "height" => 101,
            "videocodecid" => "vc",
            "framerate" => 30,
            "videodatarate" => 102,
            "audiocodecid" => "ac",
            "audiodatarate" => 103,
            "audiosamplerate" => 104,
            "audiochannels" => 105,
            "stereo" => true,
            "encoder" => "encoder"
          }
        ]
      }
    }} when timestamp > 0
  end

  test "Active publisher can send audio data to server", context do
    %TestContext{
      session: session,
      stream_key: stream_key,
      active_stream_id: stream_id,
    } = get_publishing_session(context)

    assert :ok == Handler.publish_av_data(session, stream_key, :audio, 512, <<123::23>>)
    assert_receive {:message, %DetailedMessage{
      stream_id: ^stream_id,
      timestamp: 512,
      content: %Messages.AudioData{data: <<123::23>>},
    }}
  end

  test "Active publisher can send video data to server", context do
    %TestContext{
      session: session,
      stream_key: stream_key,
      active_stream_id: stream_id,
    } = get_publishing_session(context)

    assert :ok == Handler.publish_av_data(session, stream_key, :video, 512, <<123::23>>)
    assert_receive {:message, %DetailedMessage{
      stream_id: ^stream_id,
      timestamp: 512,
      content: %Messages.VideoData{data: <<123::23>>},
    }}
  end

  defp get_connected_session(context) do
    :timer.sleep(20) # for non-zero timestamp checking

    test_context = %TestContext{
      session: context[:session],
      options: context[:options],
      app_name: "test_name"
    }

    assert :ok == Handler.request_connection(test_context.session, test_context.app_name)

    expect_connection_request_rtmp_message(test_context.app_name, test_context.options.flash_version)
    simulate_connect_response(test_context.session, true)
    expect_connection_response_received_event(true)

    test_context
  end

  defp get_playback_session(context) do
    test_context = get_connected_session(context)    

    stream_key = "abcdefg"
    created_stream_id = 5

    assert :ok == Handler.request_playback(test_context.session, stream_key)
    transaction_id = expect_create_stream_rtmp_message()

    simulate_create_stream_response(test_context.session, transaction_id, created_stream_id)    
    expect_buffer_length_rtmp_message(created_stream_id, test_context.options.playback_buffer_length_ms)
    play_transaction_id = expect_play_rtmp_message(created_stream_id, stream_key)

    description = "Started playing"
    simulate_play_response(test_context.session, play_transaction_id, created_stream_id, true, description)
    expect_play_response_received_event(true, description)

    %{test_context | 
      stream_key: stream_key,
      active_stream_id: created_stream_id
    }
  end

  defp get_publishing_session(context) do
    test_context = get_connected_session(context)

    stream_key = "abcdefg"
    created_stream_id = 5

    assert :ok == Handler.request_publish(test_context.session, stream_key, :live)
    transaction_id = expect_create_stream_rtmp_message()
    
    simulate_create_stream_response(test_context.session, transaction_id, created_stream_id)
    transaction_id = expect_publish_rtmp_message(created_stream_id, stream_key, "live")
    
    simulate_publish_response(test_context.session, transaction_id, created_stream_id, true, "success")
    expect_publish_response_received_event(stream_key, true, "success")

    %{test_context | 
      stream_key: stream_key,
      active_stream_id: created_stream_id
    }
  end

  defp simulate_connect_response(session, is_success, description \\ "success") do
    case is_success do
      true ->
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
              "description" => description,
              "objectEncoding" => 0
            }]
          }
        }

        assert :ok == Handler.handle_rtmp_input(session, command) 
    end
  end

  defp simulate_create_stream_response(session, transaction_id, stream_id) do
    create_stream_response = %DetailedMessage{
      stream_id: 0,
      content: %Messages.Amf0Command{
        command_name: "_result",
        transaction_id: transaction_id,
        command_object: nil,
        additional_values: [stream_id]
      }
    }

    assert :ok == Handler.handle_rtmp_input(session, create_stream_response)
  end

  defp simulate_play_response(session, _transaction_id, stream_id, was_accepted, description) do
    if was_accepted do
      start_command = %DetailedMessage{
        stream_id: stream_id,
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
    end
  end

  defp simulate_publish_response(session, _transaction_id, stream_id, was_accepted, description) do
    if was_accepted do
      start_command = %DetailedMessage{
        stream_id: stream_id,
        content: %Messages.Amf0Command{
          command_name: "onStatus",
          transaction_id: 0,
          command_object: nil,
          additional_values: [%{
            "level" => "status",
            "code" => "NetStream.Publish.Start",
            "description" => description
          }]
        }
      }

      assert :ok == Handler.handle_rtmp_input(session, start_command)
    end
  end

  defp expect_connection_request_rtmp_message(app_name, flash_version) do
    assert_receive {:message, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %Messages.Amf0Command{
        command_name: "connect",
        transaction_id: 1,
        command_object: %{
          "app" => ^app_name,
          "flashVer" => ^flash_version,
          "objectEncoding" => 0
        },
        additional_values: []
      }
    }} when timestamp > 0
  end

  defp expect_connection_response_received_event(was_accepted, description \\ nil) do
    if description == nil do
      assert_receive {:event, %Events.ConnectionResponseReceived{
        was_accepted: ^was_accepted
      }}
    else
      assert_receive {:event, %Events.ConnectionResponseReceived{
        was_accepted: ^was_accepted,
        response_text: ^description
      }}
    end
  end

  defp expect_create_stream_rtmp_message() do
    assert_receive {:message, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %Messages.Amf0Command{
        command_name: "createStream",
        transaction_id: transaction_id,
        command_object: nil,
        additional_values: []
      }
    }} when timestamp > 0

    transaction_id
  end

  defp expect_buffer_length_rtmp_message(stream_id, buffer_length) do
    assert_receive {:message, %DetailedMessage{
      stream_id: 0,
      content: %Messages.UserControl{
        type: :set_buffer_length,
        stream_id: ^stream_id,
        buffer_length: ^buffer_length
      }
    }}
  end

  defp expect_play_rtmp_message(stream_id, stream_key) do
    assert_receive {:message, %DetailedMessage{
      stream_id: ^stream_id,
      content: %Messages.Amf0Command{
        command_name: "play",
        transaction_id: transaction_id,
        command_object: nil,
        additional_values: [^stream_key]
      }
    }}

    transaction_id
  end

  defp expect_play_response_received_event(was_accepted, description) do
    if description == nil do
      assert_receive {:event, %Events.PlayResponseReceived{
        was_accepted: ^was_accepted,
      }}
    else
      assert_receive {:event, %Events.PlayResponseReceived{
        was_accepted: ^was_accepted,
        response_text: ^description
      }}
    end
  end

  defp expect_publish_rtmp_message(stream_id, stream_key, type) do
    assert_receive {:message, %DetailedMessage{
      stream_id: ^stream_id,
      content: %Messages.Amf0Command{
        command_name: "publish",
        transaction_id: transaction_id,
        command_object: nil,
        additional_values: [^stream_key, ^type]
      }
    }}

    transaction_id
  end

  defp expect_publish_response_received_event(stream_key, was_accepted, description) do
    if description == nil do
      assert_receive {:event, %Events.PublishResponseReceived{
        stream_key: ^stream_key,
        was_accepted: ^was_accepted,
      }}
    else
      assert_receive {:event, %Events.PublishResponseReceived{
        stream_key: ^stream_key,
        was_accepted: ^was_accepted,
        response_text: ^description
      }}
    end
  end
end