defmodule Rtmp.ServerSession.HandlerTest do
  use ExUnit.Case, async: true

  alias Rtmp.ServerSession.Configuration, as: Configuration
  alias Rtmp.ServerSession.Handler, as: Handler
  alias Rtmp.ServerSession.Events, as: Events
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
      fms_version: "test version",
      chunk_size: 9999,
      peer_bandwidth: 8888,
      window_ack_size: 7777
    }

    {:ok, session} = Handler.start_link(connection_id, options)
    :ok = Handler.set_event_handler(session, self(), __MODULE__)
    :ok = Handler.set_rtmp_output_handler(session, self(), __MODULE__)

    [session: session, connection_id: connection_id, options: options]
  end

  test "Connection request automatically triggers sending initial responses", context do
    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Messages.Amf0Command{
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
      content: %Messages.WindowAcknowledgementSize{size: ^expected_window_size},
      force_uncompressed: true
    }} when timestamp > 0

    assert_receive {:message, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %Messages.SetPeerBandwidth{window_size: ^expected_peer_bandwidth, limit_type: :dynamic},
      force_uncompressed: true
    }} when timestamp > 0

    assert_receive {:message, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %Messages.UserControl{type: :stream_begin, stream_id: 0},
      force_uncompressed: true
    }} when timestamp > 0

    assert_receive {:message, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %Messages.Amf0Command{
          command_name: "onBWDone",
          transaction_id: 0,
          command_object: nil,
          additional_values: [8192]
      },
    }} when timestamp > 0
  end

  test "Can accept connection request", context do
    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Messages.Amf0Command{
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
      content: %Messages.Amf0Command{
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

  test "Accepted connection responds with same object encoding value as connect request", context do
    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Messages.Amf0Command{
        command_name: "connect",
        transaction_id: 1,
        command_object: %{"app" => "some_app", "objectEncoding" => 3.0},
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
      content: %Messages.Amf0Command{
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
          "objectEncoding" => 3
        }]
      }
    }} when timestamp > 0
  end

  test "Can create stream on connected session", context do
    %TestContext{session: session} = get_connected_session(context)

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Messages.Amf0Command{
        command_name: "createStream",
        transaction_id: 4,
        command_object: nil,
        additional_values: []
      }
    }

    assert :ok = Handler.handle_rtmp_input(session, command)
    assert_receive {:message, %DetailedMessage{
      stream_id: 0,
      timestamp: timestamp,
      content: %Messages.Amf0Command{
        command_name: "_result",
        transaction_id: 4,
        command_object: nil,
        additional_values: [stream_id]
      }
    }} when timestamp > 0 and is_number(stream_id)

  end

  test "Can accept live publishing to requested stream key", context do
    %TestContext{
      session: session,
      active_stream_id: active_stream_id,
      app_name: app_name
    } = get_connected_session_with_active_stream(context)

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: active_stream_id,
      content: %Messages.Amf0Command{
        command_name: "publish",
        transaction_id: 0,
        command_object: nil,
        additional_values: ["stream_key", "live"]
      }
    }

    assert :ok = Handler.handle_rtmp_input(session, command)
    assert_receive {:event, %Events.PublishStreamRequested{
      app_name: ^app_name,
      stream_key: "stream_key",
      stream_id: ^active_stream_id,
      request_id: request_id
    }}

    assert :ok = Handler.accept_request(session, request_id)
    assert_receive {:message, %DetailedMessage{
        stream_id: ^active_stream_id,
        timestamp: timestamp,
        content: %Messages.Amf0Command{
          command_name: "onStatus",
          transaction_id: 0,
          command_object: nil,
          additional_values: [%{
            "level" => "status",
            "code" => "NetStream.Publish.Start",
            "description" => _
          }]
        }
      }
    } when timestamp > 0
  end

  test "Can receive and raise event for metadata from OBS", context do
    %TestContext{
      session: session,
      app_name: application_name,
      active_stream_id: stream_id,
      stream_key: stream_key
    } = get_publishing_session(context)

    message = %DetailedMessage{
      timestamp: 0,
      stream_id: stream_id,
      content: %Messages.Amf0Data{parameters: [
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

    assert :ok = Handler.handle_rtmp_input(session, message)
    assert_receive {:event, %Events.StreamMetaDataChanged{
      app_name: ^application_name,
      stream_key: ^stream_key,
      meta_data: %Rtmp.StreamMetadata{
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
    }}
  end

  test "Can receive audio data on published stream", context do
    %TestContext{
      session: session,
      app_name: application_name,
      active_stream_id: stream_id,
      stream_key: stream_key
    } = get_publishing_session(context)

    message = %DetailedMessage{
      timestamp: 500,
      stream_id: stream_id,
      content: %Messages.AudioData{data: <<1,2,3>>}
    }

    assert :ok = Handler.handle_rtmp_input(session, message)
    assert_receive {:event, %Events.AudioVideoDataReceived{
      app_name: ^application_name,
      stream_key: ^stream_key,
      data_type: :audio,
      data: <<1,2,3>>,
      timestamp: 500
    }}
  end

  test "Can receive video data on published stream", context do
    %TestContext{
      session: session,
      app_name: application_name,
      active_stream_id: stream_id,
      stream_key: stream_key
    } = get_publishing_session(context)

    message = %DetailedMessage{
      timestamp: 500,
      stream_id: stream_id,
      content: %Messages.VideoData{data: <<1,2,3>>}
    }

    assert :ok = Handler.handle_rtmp_input(session, message)
    assert_receive {:event, %Events.AudioVideoDataReceived{
      app_name: ^application_name,
      stream_key: ^stream_key,
      data_type: :video,
      data: <<1,2,3>>,
      timestamp: 500
    }}
  end

  test "Publish finished event raised when deleteStream invoked on publishing stream id", context do
    %TestContext{
      session: session,
      app_name: application_name,
      active_stream_id: stream_id,
      stream_key: stream_key
    } = get_publishing_session(context)

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Messages.Amf0Command{
        command_name: "deleteStream",
        transaction_id: 8,
        command_object: nil,
        additional_values: [stream_id]
      }
    }

    assert :ok = Handler.handle_rtmp_input(session, command)
    assert_receive {:event, %Events.PublishingFinished{
      app_name: ^application_name,
      stream_key: ^stream_key
    }}
  end

  test "Connect request strips trailing slash", context do
    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Messages.Amf0Command{
        command_name: "connect",
        transaction_id: 1,
        command_object: %{"app" => "some_app/"},
        additional_values: []
      }
    }

    assert :ok = Handler.handle_rtmp_input(context.session, command)
    assert_receive {:event, %Events.ConnectionRequested{
      request_id: _,
      app_name: "some_app"
    }}
  end

  test "Can accept play command with all optional parameters to requested stream key", context do
    %TestContext{
      session: session,
      active_stream_id: active_stream_id,
      app_name: app_name
    } = get_connected_session_with_active_stream(context)

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: active_stream_id,
      content: %Messages.Amf0Command{
        command_name: "play",
        transaction_id: 0,
        command_object: nil,
        additional_values: ["stream_key", -2, -1, false]
      }
    }

    assert :ok = Handler.handle_rtmp_input(session, command)
    assert_receive {:event, %Events.PlayStreamRequested{
      app_name: ^app_name,
      stream_key: "stream_key",
      video_type: :any,
      start_at: 0,
      duration: -1,
      reset: false,
      stream_id: ^active_stream_id,
      request_id: request_id
    }}

    assert :ok = Handler.accept_request(session, request_id)
    assert_receive {:message, %DetailedMessage{
      stream_id: ^active_stream_id,
      timestamp: timestamp,
      content: %Messages.UserControl{
        type: :stream_begin,
        stream_id: ^active_stream_id
      }
    }} when timestamp > 0

    assert_receive {:message, %DetailedMessage{
      stream_id: ^active_stream_id,
      timestamp: timestamp,
      content: %Messages.Amf0Command{
        command_name: "onStatus",
        transaction_id: 0,
        command_object: nil,
        additional_values: [%{
          "level" => "status",
          "code" => "NetStream.Play.Start",
          "description" => _
        }]
      }
    }} when timestamp > 0

    assert_receive {:message, %DetailedMessage{
      stream_id: ^active_stream_id,
      timestamp: timestamp,
      content: %Messages.Amf0Data{
        parameters: [
          "|RtmpSampleAccess",
          false,
          false
        ]
      }
    }} when timestamp > 0

    assert_receive {:message, %DetailedMessage{
      stream_id: ^active_stream_id,
      timestamp: timestamp,
      content: %Messages.Amf0Data{
        parameters: [
          "onStatus",
          %{"code" => "NetStream.Data.Start"}
        ]
      }
    }} when timestamp > 0
  end

  test "Can accept play command with no optional parameters to requested stream key", context do
    %TestContext{
      session: session,
      active_stream_id: active_stream_id,
      app_name: app_name
    } = get_connected_session_with_active_stream(context)

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: active_stream_id,
      content: %Messages.Amf0Command{
        command_name: "play",
        transaction_id: 0,
        command_object: nil,
        additional_values: ["stream_key"]
      }
    }

    assert :ok = Handler.handle_rtmp_input(session, command)
    assert_receive {:event, %Events.PlayStreamRequested{
      app_name: ^app_name,
      stream_key: "stream_key",
      video_type: :any,
      start_at: 0,
      duration: -1,
      reset: true,
      stream_id: ^active_stream_id,
      request_id: request_id
    }}

    assert :ok = Handler.accept_request(session, request_id)
    assert_receive {:message, %DetailedMessage{
      stream_id: ^active_stream_id,
      timestamp: timestamp,
      content: %Messages.UserControl{
        type: :stream_begin,
        stream_id: ^active_stream_id
      }
    }} when timestamp > 0

    assert_receive {:message, %DetailedMessage{
      stream_id: ^active_stream_id,
      timestamp: timestamp,
      content: %Messages.Amf0Command{
        command_name: "onStatus",
        transaction_id: 0,
        command_object: nil,
        additional_values: [%{
          "level" => "status",
          "code" => "NetStream.Play.Reset",
          "description" => _
        }]
      }
    }} when timestamp > 0

    assert_receive {:message, %DetailedMessage{
      stream_id: ^active_stream_id,
      timestamp: timestamp,
      content: %Messages.Amf0Command{
        command_name: "onStatus",
        transaction_id: 0,
        command_object: nil,
        additional_values: [%{
          "level" => "status",
          "code" => "NetStream.Play.Start",
          "description" => _
        }]
      }
    }} when timestamp > 0

    assert_receive {:message, %DetailedMessage{
      stream_id: ^active_stream_id,
      timestamp: timestamp,
      content: %Messages.Amf0Data{parameters: ["|RtmpSampleAccess", false, false]
      }
    }} when timestamp > 0

    assert_receive {:message, %DetailedMessage{
      stream_id: ^active_stream_id,
      timestamp: timestamp,
      content: %Messages.Amf0Data{
        parameters: [
          "onStatus",
          %{"code" => "NetStream.Data.Start"}
        ]
      }
    }} when timestamp > 0
  end

  test "Closing publishing stream raises publishing finished event", context do
    %TestContext{
      session: session,
      app_name: application_name,
      active_stream_id: stream_id,
      stream_key: stream_key
    } = get_publishing_session(context)

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: stream_id,
      content: %Messages.Amf0Command{
        command_name: "closeStream",
        transaction_id: 8,
        command_object: nil,
        additional_values: [stream_id]
      }
    }

    assert :ok = Handler.handle_rtmp_input(session, command)
    assert_receive {:event, %Events.PublishingFinished{
      app_name: ^application_name,
      stream_key: ^stream_key
    }}
  end

  test "Can request publishing on closed stream", context do
    %TestContext{
      session: session,
      app_name: application_name,
      active_stream_id: stream_id,
      stream_key: stream_key
    } = get_publishing_session(context)

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: stream_id,
      content: %Messages.Amf0Command{
        command_name: "closeStream",
        transaction_id: 8,
        command_object: nil,
        additional_values: [stream_id]
      }
    }

    assert :ok = Handler.handle_rtmp_input(session, command)

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: stream_id,
      content: %Messages.Amf0Command{
        command_name: "publish",
        transaction_id: 0,
        command_object: nil,
        additional_values: [stream_key, "live"]
      }
    }

    assert :ok = Handler.handle_rtmp_input(session, command)
    assert_receive {:event, %Events.PublishStreamRequested{
      app_name: ^application_name,
      stream_key: ^stream_key
    }}
  end

  test "Closing playing stream reaises play finished event", context do
    %TestContext{
      session: session,
      app_name: application_name,
      active_stream_id: stream_id,
      stream_key: stream_key
    } = get_playing_session(context)

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: stream_id,
      content: %Messages.Amf0Command{
        command_name: "closeStream",
        transaction_id: 8,
        command_object: nil,
        additional_values: [stream_id]
      }
    }

    assert :ok = Handler.handle_rtmp_input(session, command)
    assert_receive {:event, %Events.PlayStreamFinished{
      app_name: ^application_name,
      stream_key: ^stream_key
    }}
  end

  test "Can request play on closed stream", context do
    %TestContext{
      session: session,
      app_name: application_name,
      active_stream_id: stream_id,
      stream_key: stream_key
    } = get_publishing_session(context)

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: stream_id,
      content: %Messages.Amf0Command{
        command_name: "closeStream",
        transaction_id: 8,
        command_object: nil,
        additional_values: [stream_id]
      }
    }

    assert :ok = Handler.handle_rtmp_input(session, command)

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: stream_id,
      content: %Messages.Amf0Command{
        command_name: "play",
        transaction_id: 0,
        command_object: nil,
        additional_values: [stream_key]
      }
    }

    assert :ok = Handler.handle_rtmp_input(session, command)
    assert_receive {:event, %Events.PlayStreamRequested{
      app_name: ^application_name,
      stream_key: ^stream_key,
      video_type: :any,
      start_at: 0,
      duration: -1,
      reset: true
    }}

  end

  defp get_connected_session(context) do
    # Make sure some time has passed since creating the processor
    #   to allow for non-zero timestamp checking
    :timer.sleep(100)

    test_context = %TestContext{
      session: context[:session],
      options: context[:options],
      app_name: "test_app"
    }

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Messages.Amf0Command{
        command_name: "connect",
        transaction_id: 1,
        command_object: %{"app" => test_context.app_name}
      }
    }

    assert :ok = Handler.handle_rtmp_input(test_context.session, command)
    assert_receive {:event, %Events.ConnectionRequested{app_name: "test_app", request_id: request_id}}
    assert :ok = Handler.accept_request(test_context.session, request_id)

    test_context
  end

  defp get_connected_session_with_active_stream(context) do
    test_context = get_connected_session(context)

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %Messages.Amf0Command{
        command_name: "createStream",
        transaction_id: 4,
        command_object: nil,
        additional_values: []
      }
    }

    assert :ok = Handler.handle_rtmp_input(test_context.session, command)
    assert_receive {:message, %DetailedMessage{
      content: %Messages.Amf0Command{
        command_name: "_result",
        transaction_id: 4,
        additional_values: [stream_id]
      }
    }}

    %{test_context | active_stream_id: stream_id}

  end

  defp get_publishing_session(context) do
    test_context = get_connected_session_with_active_stream(context)

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: test_context.active_stream_id,
      content: %Messages.Amf0Command{
        command_name: "publish",
        transaction_id: 0,
        command_object: nil,
        additional_values: ["stream_key", "live"]
      }
    }

    assert :ok = Handler.handle_rtmp_input(test_context.session, command)
    assert_receive {:event, %Events.PublishStreamRequested{request_id: request_id}}
    assert :ok = Handler.accept_request(test_context.session, request_id)

    %{test_context | stream_key: "stream_key"}
  end

  defp get_playing_session(context) do
    test_context = get_connected_session_with_active_stream(context)

    command = %DetailedMessage{
      timestamp: 0,
      stream_id: test_context.active_stream_id,
      content: %Messages.Amf0Command{
        command_name: "play",
        transaction_id: 0,
        command_object: nil,
        additional_values: ["stream_key"]
      }
    }

    assert :ok = Handler.handle_rtmp_input(test_context.session, command)
    assert_receive {:event, %Events.PlayStreamRequested{request_id: request_id}}
    assert :ok = Handler.accept_request(test_context.session, request_id)

    %{test_context | stream_key: "stream_key"}
  end
end