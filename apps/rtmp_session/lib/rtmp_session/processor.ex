defmodule RtmpSession.Processor do
  @moduledoc """
  The RTMP session processor represents the core finite state machine dictating
  how incoming RTMP messages should be handled, including determining what RTMP messages
  should be sent to the peer and what events the session needs to react to.
  """

  alias RtmpSession.DetailedMessage, as: DetailedMessage
  alias RtmpSession.Messages, as: MessageTypes
  alias RtmpSession.Events, as: Events
  alias RtmpSession.SessionConfig, as: SessionConfig
  alias RtmpSession.StreamMetadata, as: StreamMetadata

  require Logger

  @type handle_result :: {:response, DetailedMessage.t} | {:event, Events.t}

  defmodule State do
    defstruct current_stage: :started,
      start_time: :os.system_time(:milli_seconds),
      peer_window_ack_size: nil,
      peer_bytes_received: 0,
      last_acknowledgement_sent_at: 0,
      configuration: nil,
      active_requests: %{},
      last_request_id: 0,
      last_created_stream_id: 0,
      connected_app_name: nil,
      active_streams: %{},
      session_id: nil
  end

  defmodule ActiveStream do
    defstruct stream_id: nil,
              current_state: :created,
              stream_key: nil
  end

  @spec new(%SessionConfig{}, String.t) :: %State{}
  def new(config = %SessionConfig{}, session_id) do
    %State{
      configuration: config,
      session_id: session_id
    }
  end

  @spec notify_bytes_received(%State{}, non_neg_integer()) :: {%State{}, [handle_result]}
  def notify_bytes_received(state = %State{}, bytes_received) do
    state = %{state | peer_bytes_received: state.peer_bytes_received + bytes_received}
    bytes_since_last_ack = state.peer_bytes_received - state.last_acknowledgement_sent_at
    
    cond do
      state.peer_window_ack_size == nil ->
        {state, []}

      bytes_since_last_ack < state.peer_window_ack_size ->
        {state, []}

      true ->
        state = %{state | last_acknowledgement_sent_at: state.peer_bytes_received }
        ack_message = %MessageTypes.Acknowledgement{sequence_number: state.peer_bytes_received}
        results = [{:response, form_response_message(state, ack_message, 0)}]
        {state, results}
    end
  end

  @spec handle(%State{}, DetailedMessage.t) :: {%State{}, [handle_result]}
  def handle(state = %State{}, message = %DetailedMessage{}) do
    do_handle(state, message)
  end

  @spec accept_request(%State{}, non_neg_integer()) :: {%State{}, [handle_result]}
  def accept_request(state = %State{}, request_id) do
    request = Map.fetch!(state.active_requests, request_id)
    state = %{state | active_requests: Map.delete(state.active_requests, request_id)}

    case request do
      {:connect, app_name} -> accept_connect_request(state, app_name)
      {:publish, {sid, stream_key}} -> accept_publish_request(state, sid, stream_key)
    end
  end

  defp do_handle(state, %DetailedMessage{content: %MessageTypes.SetChunkSize{size: size}}) do
    {state, [{:event, %Events.PeerChunkSizeChanged{new_chunk_size: size}}]}
  end

  defp do_handle(state, %DetailedMessage{content: %MessageTypes.WindowAcknowledgementSize{size: size}}) do
    state = %{state | peer_window_ack_size: size}
    {state, []}
  end

  defp do_handle(state, message = %DetailedMessage{content: %MessageTypes.Amf0Command{}}) do
    handle_command(state, 
                   message.stream_id, 
                   message.content.command_name, 
                   message.content.transaction_id, 
                   message.content.command_object,
                   message.content.additional_values)
  end

  defp do_handle(state, message = %DetailedMessage{content: %MessageTypes.Amf0Data{}}) do
    active_stream = Map.fetch!(state.active_streams, message.stream_id)
    handle_data(state, active_stream, message.content.parameters)
  end

  defp do_handle(state, message = %DetailedMessage{content: %MessageTypes.AudioData{}}) do
    active_stream = Map.fetch!(state.active_streams, message.stream_id)
    if active_stream.current_state != :publishing do
      error_message = "Client attempted to send audio data on stream in state #{active_stream.current_state}"
      raise_error(state, error_message)
    end

    event = {:event, %Events.AudioVideoDataReceived{
      app_name: state.connected_app_name,
      stream_key: active_stream.stream_key,
      data_type: :audio,
      data: message.content.data
    }}

    {state, [event]}
  end

  defp do_handle(state, message = %DetailedMessage{content: %MessageTypes.VideoData{}}) do
    active_stream = Map.fetch!(state.active_streams, message.stream_id)
    if active_stream.current_state != :publishing do
      error_message = "Client attempted to send video data on stream in state #{active_stream.current_state}"
      raise_error(state, error_message)
    end

    event = {:event, %Events.AudioVideoDataReceived{
      app_name: state.connected_app_name,
      stream_key: active_stream.stream_key,
      data_type: :video,
      data: message.content.data
    }}

    {state, [event]}
  end

  defp do_handle(state, message = %DetailedMessage{content: %{__struct__: message_type}}) do
    simple_name = String.replace(to_string(message_type), "Elixir.RtmpSession.Messages.", "")

    _ = log(state, :info, "Unable to handle #{simple_name} message on stream id #{message.stream_id}")
    {state, []}
  end

  defp handle_command(state = %State{current_stage: :started}, _stream_id, "connect", _transaction_id, command_obj, _args) do
    _ = log(state, :debug, "Connect command received")

    app_name = command_obj["app"]
    request = {:connect, app_name}
    {state, request_id} = create_request(state, request)

    # FYI, sending a SetChunkSize here before connection is accepted will break OBS
    responses = [
      {
        :response, 
        form_response_message(state,
          %MessageTypes.SetPeerBandwidth{window_size: state.configuration.peer_bandwidth, limit_type: :dynamic},
          0, true)  
      },
      {
        :response,
        form_response_message(state,
          %MessageTypes.WindowAcknowledgementSize{size: state.configuration.window_ack_size},
          0, true)
      },
      {
        :response,
        form_response_message(state,
          %MessageTypes.UserControl{type: :stream_begin, stream_id: 0},
          0, true)
      }
    ]

    events = [
      {:event, %Events.ConnectionRequested{
        request_id: request_id,
        app_name: app_name
      }}
    ]

    {state, responses ++ events}
  end

  defp handle_command(state = %State{current_stage: :connected}, 
                      _stream_id, 
                      "createStream", 
                      transaction_id, 
                      _command_obj, 
                      _args) do
    _ = log(state, :debug, "createStream command received")

    new_stream_id = state.last_created_stream_id + 1
    state = %{state |
      last_created_stream_id: new_stream_id,
      active_streams: Map.put(state.active_streams, new_stream_id, %ActiveStream{stream_id: new_stream_id})
    }

    response = {:response, form_response_message(state,
        %MessageTypes.Amf0Command{
          command_name: "_result",
          transaction_id: transaction_id,
          command_object: nil,
          additional_values: [new_stream_id]
        }, 0)
    }

    _ = log(state, :debug, "Created stream id #{new_stream_id}")

    {state, [response]}
  end

  defp handle_command(state = %State{current_stage: :connected}, 
                      stream_id, 
                      "publish", 
                      _transaction_id, 
                      nil, 
                      [stream_key, "live"]) do
    _ = log(state, :debug, "Received publish command on stream '#{stream_id}'")

    case Map.fetch!(state.active_streams, stream_id) do
      %ActiveStream{current_state: :created} ->
        request = {:publish, {stream_id, stream_key}}
        {state, request_id} = create_request(state, request)

        event = {:event, %Events.PublishStreamRequested{
          request_id: request_id,
          app_name: state.connected_app_name,
          stream_key: stream_key
        }}

        {state, [event]}

      %ActiveStream{current_state: stream_state} ->
        _ = log(state, :info, "Bad attempt made to publish on stream id #{stream_id} " <>
          "that's in state '#{stream_state}'")

        {state, []}
    end
  end

  defp handle_command(state = %State{current_stage: :connected}, 
                      _stream_id, 
                      "deleteStream", 
                      _transaction_id, 
                      nil, 
                      [stream_id_to_delete]) do
    _ = log(state, :debug, "Received deleteStream command")

    case Map.fetch(state.active_streams, stream_id_to_delete) do
      {:ok, stream = %ActiveStream{}} ->
        state = %{state | active_streams: Map.delete(state.active_streams, stream_id_to_delete)}

        event = {:event, %Events.PublishingFinished{
          app_name: state.connected_app_name,
          stream_key: stream.stream_key
        }}

        {state, [event]}

      :error ->
        # Since this is not an active stream, ignore the request
        {state, []}
    end
  end

  defp handle_command(state, stream_id, command_name, transaction_id, _command_obj, _args) do
    _ = log(state, :info, "Unable to handle command '#{command_name}' while in stage '#{state.current_stage}' " <>
      "(stream id '#{stream_id}', transaction_id: #{transaction_id})")
    {state, []}
  end
  
  defp handle_data(state, stream = %ActiveStream{current_state: :publishing}, ["@setDataFrame", "onMetaData", metadata = %{}]) do
    event = {:event, %Events.StreamMetaDataChanged{
      app_name: state.connected_app_name,
      stream_key: stream.stream_key,
      meta_data: %StreamMetadata{
        video_width: metadata["width"],
        video_height: metadata["height"],
        video_codec: metadata["videocodecid"],
        video_frame_rate: metadata["framerate"],
        video_bitrate_kbps: metadata["videodatarate"],
        audio_codec: metadata["audiocodecid"],
        audio_bitrate_kbps: metadata["audiodatarate"],
        audio_sample_rate: metadata["audiosamplerate"],
        audio_channels: metadata["audiochannels"],
        audio_is_stereo: metadata["stereo"],
        encoder: metadata["encoder"]
      }
    }}

    {state, [event]}
  end

  defp handle_data(state, stream, data) do
    _ = log(state, :info, "No known way to handle incoming data on stream id '#{stream.stream_id}' " <>
      "in state #{stream.current_state}.  Data: #{inspect data}")

    {state, []}
  end

  defp accept_connect_request(state, application_name) do
    _ = log(state, :debug, "Accepted connection request for application '#{application_name}'")

    state = %{state |
      current_stage: :connected,
      connected_app_name: application_name 
    }

    response = {:response, form_response_message(state,
      %MessageTypes.Amf0Command{
        command_name: "_result",
        transaction_id: 1,
        command_object: %{
          "fmsVer" => state.configuration.fms_version,
          "capabilities" => 31
        },
        additional_values: [%{
          "level" => "status",
          "code" => "NetConnection.Connect.Success",
          "description" => "Connection succeeded",
          "objectEncoding" => 0
        }]
      }, 0)
    }

    chunk_size_response = {:response, 
      form_response_message(state, %MessageTypes.SetChunkSize{size: state.configuration.chunk_size}, 0)
    }

    {state, [response, chunk_size_response]}
  end

  defp accept_publish_request(state, stream_id, stream_key) do
    active_stream = Map.fetch!(state.active_streams, stream_id)
    if active_stream.current_state != :created do
      message = "Attempted to accept publish request on stream id #{stream_id} that's in state '#{active_stream.current_state}'"
      raise_error(state, message)
    end

    active_stream = %{active_stream |
      current_state: :publishing,
      stream_key: stream_key
    }

    state = %{state |
      active_streams: Map.put(state.active_streams, stream_id, active_stream)
    }

    response = {:response, form_response_message(state, %MessageTypes.Amf0Command{
        command_name: "onStatus",
        transaction_id: 0,
        command_object: nil,
        additional_values: [%{
          "level" => "status",
          "code" => "NetStream.Publish.Start",
          "description" => "#{stream_key} is now published."
        }]
      }, stream_id)
    }

    {state, [response]}
  end

  defp create_request(state, request) do
    request_id = state.last_request_id + 1
    state = %{state | 
      last_request_id: request_id,
      active_requests: Map.put(state.active_requests, request_id, request)
    }

    {state, request_id}
  end

  defp form_response_message(state, message_content, stream_id, force_uncompressed \\ false) do
    %DetailedMessage{
      timestamp: get_current_rtmp_epoch(state),
      stream_id: stream_id,
      content: message_content,
      force_uncompressed: force_uncompressed
    }
  end

  defp log(state, level, message) do
    case level do
      :debug -> Logger.debug "#{state.session_id}: #{message}"
      :info -> Logger.info "#{state.session_id}: #{message}"
    end
  end

  @spec raise_error(%State{}, String.t) :: no_return()
  defp raise_error(_state, message) do
    # TODO: Add session id to message
    raise(message)
  end

  defp get_current_rtmp_epoch(state) do
    time_since_start = :os.system_time(:milli_seconds) - state.start_time
    RtmpSession.RtmpTime.to_rtmp_timestamp(time_since_start)
  end
end