defmodule Rtmp.ServerSession.Handler do
  @moduledoc """
  This module controls the process that controls the business logic
  of a server in an RTMP connection.

  The session handler can react to incoming RTMP input messages from
  the client by responding directly with RTMP output messages or by
  sending out event notifications for other processes to react to.

  The session handler then has an API for other processes to proactively
  trigger business logic (such as accepting a connection request) and cause
  RTMP messages to be sent out to the connected client.
  """

  require Logger
  use GenServer

  alias Rtmp.Protocol.DetailedMessage, as: DetailedMessage
  alias Rtmp.Protocol.Messages, as: Messages
  alias Rtmp.ServerSession.Events, as: Events
  alias Rtmp.ServerSession.Configuration, as: Configuration

  @type rtmp_output_handler :: pid
  @type session_handler :: pid
  @type event_notification_process :: pid
  @type protocol_handler_module :: module
  @type event_receiver_process :: pid
  @type event_receiver_module ::  module
  @type request_id :: non_neg_integer

  defmodule State do
    @moduledoc false

    defstruct connection_id: nil,
              configuration: nil,
              start_time: nil,
              protocol_handler_pid: nil,
              protocol_handler_module: nil,
              event_receiver_pid: nil,
              event_receiver_module: nil,
              current_stage: :started,
              specified_amf_version: 0,
              last_request_id: 0,
              active_requests: %{},
              connected_app_name: nil,
              last_created_stream_id: 0,
              active_streams: %{}
  end

  defmodule ActiveStream do
    @moduledoc false

    defstruct stream_id: nil,
              current_state: :created,
              stream_key: nil,
              buffer_size_in_ms: nil
  end

  defmodule PlayArguments do
    @moduledoc false

    defstruct start_at: -2, # default to live or recorded
              duration: -1, # full duration
              is_reset: true
  end

  @spec start_link(Rtmp.connection_id, Configuration.t) :: {:ok, session_handler}
  @doc "Starts a new session handler process"
  def start_link(connection_id, configuration = %Configuration{}) do
    GenServer.start_link(__MODULE__, [connection_id, configuration])
  end

  @spec set_event_handler(session_handler, event_notification_process, event_receiver_module)
    :: :ok | :event_handler_already_set
  @doc "Specifies the process id and function to use to raise event notifications"
  def set_event_handler(session_pid, event_pid, event_receiver_module) do
    GenServer.call(session_pid, {:set_event_handler, {event_pid, event_receiver_module}})
  end

  @spec set_rtmp_output_handler(session_handler, rtmp_output_handler, protocol_handler_module)
    :: :ok | :output_handler_already_set
  @doc "Specifies the process id and function to send outbound RTMP messages"
  def set_rtmp_output_handler(session_pid, protocol_handler_pid, protocol_handler_module) do
    GenServer.call(session_pid, {:set_output_handler, {protocol_handler_pid, protocol_handler_module}})
  end

  @spec handle_rtmp_input(session_handler, DetailedMessage.t) :: :ok
  @doc "Passes an incoming RTMP message to the session handler"
  def handle_rtmp_input(pid, message = %DetailedMessage{}) do
    GenServer.cast(pid, {:rtmp_input, message})
  end

  @spec send_rtmp_message(session_handler, Rtmp.deserialized_message, non_neg_integer, non_neg_integer | nil) :: :ok
  @doc "Forms an RTMP detailed message with the specified message contents to be sent to the client"
  def send_rtmp_message(pid, message, stream_id, forced_timestamp \\ nil) do
    GenServer.cast(pid, {:send_message, {message, stream_id, forced_timestamp}})
  end

  @spec send_stream_zero_begin(session_handler) :: :ok
  @doc "Sends the client the initial RTMP messages allowing the client to send messages on stream id 0"
  def send_stream_zero_begin(pid) do
    GenServer.cast(pid, :begin_stream_zero)
  end

  @spec accept_request(session_handler, request_id) :: :ok
  @doc "Attempts to accept a request with the specified id"
  def accept_request(pid, request_id) do
    GenServer.cast(pid, {:accept_request, request_id})
  end

  def init([connection_id, configuration]) do
    state = %State{
      connection_id: connection_id,
      configuration: configuration,
      start_time: :os.system_time(:milli_seconds)
    }

    {:ok, state}
  end

  def handle_call({:set_event_handler, {event_pid, event_receiver_module}}, _from, state) do
    handler_set = state.event_receiver_pid != nil
    function_set = state.event_receiver_module != nil
    case handler_set && function_set do
      true ->
        {:reply, :event_handler_already_set, state}

      false ->
        state = %{state | event_receiver_pid: event_pid, event_receiver_module: event_receiver_module}
        {:reply, :ok, state}
    end
  end

  def handle_call({:set_output_handler, {protocol_handler_pid, protocol_handler_module}}, _from, state) do
    handler_set = state.protocol_handler_pid != nil
    function_set = state.protocol_handler_module != nil
    case handler_set && function_set do
      true ->
        {:reply, :event_handler_already_set, state}

      false ->
        state = %{state |
          protocol_handler_pid: protocol_handler_pid,
          protocol_handler_module: protocol_handler_module
        }

        {:reply, :ok, state}
    end
  end

  def handle_cast({:rtmp_input, message}, state) do
    cond do
      state.event_receiver_pid == nil -> raise("No event handler set")
      state.event_receiver_module == nil -> raise("No event handler set")
      state.protocol_handler_pid == nil -> raise("No protocol handler set")
      state.protocol_handler_module == nil -> raise("No protocol handler set")
      true ->
        state = do_handle(state, message)
        {:noreply, state}
    end
  end

  def handle_cast({:accept_request, request_id}, state) do
    {request, remaining_requests} = Map.pop(state.active_requests, request_id)
    state = %{state | active_requests: remaining_requests}

    state = case request do
      {:connect, app_name} -> accept_connect_request(state, app_name)
      {:publish, {sid, stream_key}} -> accept_publish_request(state, sid, stream_key)
      {:play, {sid, stream_key, is_reset}} -> accept_play_request(state, sid, stream_key, is_reset)
    end

    {:noreply, state}
  end

  def handle_cast({:send_message, {message, stream_id, forced_timestamp}}, state) do
    timestamp = case forced_timestamp do
      nil -> :os.system_time(:milli_seconds) - state.start_time
      x when x >= 0 -> x
    end

    detailed_message = %DetailedMessage{
      timestamp: timestamp,
      stream_id: stream_id,
      content: message
    }

    :ok = state.protocol_handler_module.send_message(state.protocol_handler_pid, detailed_message)
    {:noreply, state}
  end

  def handle_cast(:begin_stream_zero, state) do
    messages = [
      %Messages.SetPeerBandwidth{window_size: state.configuration.peer_bandwidth, limit_type: :dynamic},
      %Messages.WindowAcknowledgementSize{size: state.configuration.window_ack_size},
      %Messages.UserControl{type: :stream_begin, stream_id: 0},
      %Messages.Amf0Command{
        command_name: "onBWDone",
        transaction_id: 0,
        command_object: nil,
        additional_values: [8192]
      } # based on packet capture, not sure if 100% needed
    ]

    :ok = send_output_message(state, messages, 0, true)
    {:noreply, state}
  end

  defp do_handle(state, message = %DetailedMessage{content: %Messages.Amf0Command{}}) do
    handle_command(state,
                   message.stream_id,
                   message.content.command_name,
                   message.content.transaction_id,
                   message.content.command_object,
                   message.content.additional_values)
  end

  defp do_handle(state, message = %DetailedMessage{content: %Messages.Amf0Data{}}) do
    active_stream = Map.fetch!(state.active_streams, message.stream_id)
    handle_data(state, active_stream, message.content.parameters)
  end

  defp do_handle(state, message = %DetailedMessage{content: %Messages.AudioData{}}) do
    active_stream = Map.fetch!(state.active_streams, message.stream_id)
    if active_stream.current_state != :publishing do
      error_message = "Client attempted to send audio data on stream in state #{active_stream.current_state}"
      raise("#{state.connection_id}: #{error_message}")
    end

    event = %Events.AudioVideoDataReceived{
      app_name: state.connected_app_name,
      stream_key: active_stream.stream_key,
      data_type: :audio,
      data: message.content.data,
      timestamp: message.timestamp,
      received_at_timestamp: message.deserialization_system_time
    }

    raise_event(state, event)
    state
  end

  defp do_handle(state, _message = %DetailedMessage{content: %Messages.SetChunkSize{}}) do
    # Ignore, nothing to do.
    state
  end

  defp do_handle(state, message = %DetailedMessage{content: %Messages.VideoData{}}) do
    active_stream = Map.fetch!(state.active_streams, message.stream_id)
    if active_stream.current_state != :publishing do
      error_message = "Client attempted to send video data on stream in state #{active_stream.current_state}"
      raise("#{state.connection_id}: #{error_message}")
    end

    event = %Events.AudioVideoDataReceived{
      app_name: state.connected_app_name,
      stream_key: active_stream.stream_key,
      data_type: :video,
      data: message.content.data,
      timestamp: message.timestamp,
      received_at_timestamp: message.deserialization_system_time
    }

    raise_event(state, event)
    state
  end

  defp do_handle(state, message = %DetailedMessage{content: %{__struct__: message_type}}) do
    simple_name = String.replace(to_string(message_type), "Elixir.Rtmp.Protocol.Messages.", "")

    _ = Logger.warn("#{state.connection_id}: Unable to handle #{simple_name} message on stream id #{message.stream_id}")
    state
  end

  defp handle_command(state = %State{current_stage: :connected},
                      stream_id,
                      "closeStream",
                      _transaction_id,
                      nil,
                      _) do
    _ = Logger.debug("#{state.connection_id}: Received closeStream command on stream #{stream_id}")

    case Map.fetch(state.active_streams, stream_id) do
      {:ok, stream = %ActiveStream{}} ->
        current_state = stream.current_state
        stream = %{stream | current_state: :created}
        state = %{state | active_streams: Map.put(state.active_streams, stream_id, stream)}

        case current_state do
          :playing ->
            event = %Events.PlayStreamFinished{
              app_name: state.connected_app_name,
              stream_key: stream.stream_key
            }

            raise_event(state, event)
            state

          :publishing ->
            event = %Events.PublishingFinished{
              app_name: state.connected_app_name,
              stream_key: stream.stream_key
            }

            raise_event(state, event)
            state

          :created -> state
        end

      :error ->
        # Since this is not an active stream, ignore the request
        state
    end

  end

  defp handle_command(state = %State{current_stage: :started},
                      _stream_id,
                      "connect",
                      _transaction_id,
                      command_obj,
                      _args) do

    state = case command_obj["objectEncoding"] do
      x when x == 3 -> %{state | specified_amf_version: 3}
      _ -> state
    end

    app_name = String.replace_trailing(command_obj["app"], "/", "")
    request = {:connect, app_name}
    {state, request_id} = create_request(state, request)

    _ = Logger.debug("#{state.connection_id}: Connect command received on app #{app_name}")

    raise_event(state, %Events.ConnectionRequested{
      request_id: request_id,
      app_name: app_name
    })

    state
  end

  defp handle_command(state = %State{current_stage: :connected},
                      _stream_id,
                      "createStream",
                      transaction_id,
                      _command_obj,
                      _args) do

    _ = Logger.debug("#{state.connection_id}: createStream command received")

    new_stream_id = state.last_created_stream_id + 1
    state = %{state |
      last_created_stream_id: new_stream_id,
      active_streams: Map.put(state.active_streams, new_stream_id, %ActiveStream{stream_id: new_stream_id})
    }

    response = %Messages.Amf0Command{
      command_name: "_result",
      transaction_id: transaction_id,
      command_object: nil,
      additional_values: [new_stream_id]
    }

    :ok = send_output_message(state, response, 0)

    _ = Logger.debug("#{state.connection_id}: Created stream id #{new_stream_id}")
    state
  end

  defp handle_command(state = %State{current_stage: :connected},
                      stream_id,
                      "play",
                      _transaction_id,
                      nil,
                      [stream_key | other_args]) do

    _ = Logger.debug("#{state.connection_id}: Received play command")

    play_arguments = parse_play_other_args(other_args)

    case Map.fetch!(state.active_streams, stream_id) do
      %ActiveStream{current_state: :created} ->
        request = {:play, {stream_id, stream_key, play_arguments.is_reset}}
        {state, request_id} = create_request(state, request)

        {video_type, start_at} = case play_arguments.start_at do
          x when x < -1 -> {:any, 0} # since VLC sends -2000, assume anything below -1 means any
          -1 -> {:live, 0}
          x when x >= 0 -> {:recorded, 0}
        end

        play_event = %Events.PlayStreamRequested{
          request_id: request_id,
          app_name: state.connected_app_name,
          stream_key: stream_key,
          video_type: video_type,
          start_at: start_at,
          duration: play_arguments.duration,
          reset: play_arguments.is_reset,
          stream_id: stream_id
        }

        raise_event(state, play_event)
        state

      %ActiveStream{current_state: stream_state} ->
        _ = Logger.debug("#{state.connection_id}: Bad attempt made to play on stream id #{stream_id} " <>
          "that's in state '#{stream_state}'")

        state
    end
  end

  defp handle_command(state = %State{current_stage: :connected},
                      stream_id,
                      "publish",
                      _transaction_id,
                      nil,
                      [stream_key, "live"]) do
    _ = Logger.debug("#{state.connection_id}: Received publish command on stream '#{stream_id}'")

    case Map.fetch!(state.active_streams, stream_id) do
      %ActiveStream{current_state: :created} ->
        request = {:publish, {stream_id, stream_key}}
        {state, request_id} = create_request(state, request)

        event = %Events.PublishStreamRequested{
          request_id: request_id,
          app_name: state.connected_app_name,
          stream_key: stream_key,
          stream_id: stream_id
        }

        raise_event(state, event)
        state

      %ActiveStream{current_state: stream_state} ->
        _ = Logger.info("#{state.connection_id}: Bad attempt made to publish on stream id #{stream_id} " <>
          "that's in state '#{stream_state}'")

        state
    end
  end

  defp handle_command(state = %State{current_stage: :connected},
                      _stream_id,
                      "deleteStream",
                      _transaction_id,
                      nil,
                      [stream_id_to_delete]) do
    _ = Logger.debug("#{state.connection_id}: Received deleteStream command")

    case Map.fetch(state.active_streams, stream_id_to_delete) do
      {:ok, stream = %ActiveStream{}} ->
        state = %{state | active_streams: Map.delete(state.active_streams, stream_id_to_delete)}

        event = %Events.PublishingFinished{
          app_name: state.connected_app_name,
          stream_key: stream.stream_key
        }

        raise_event(state, event)
        state

      :error ->
        # Since this is not an active stream, ignore the request
        state
    end
  end

  defp handle_command(state, stream_id, command_name, transaction_id, _command_obj, _args) do
    unless is_ignorable_command(command_name) do
      _ = Logger.warn("#{state.connection_id}: Unable to handle command '#{command_name}' while in stage '#{state.current_stage}' " <>
        "(stream id '#{stream_id}', transaction_id: #{transaction_id})")
    end

    state
  end

  defp handle_data(state, stream = %ActiveStream{current_state: :publishing}, ["@setDataFrame", "onMetaData", metadata = %{}]) do
    event = %Events.StreamMetaDataChanged{
      app_name: state.connected_app_name,
      stream_key: stream.stream_key,
      meta_data: %Rtmp.StreamMetadata{
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
    }

    raise_event(state, event)
    state
  end

  defp handle_data(state, stream, data) do
    _ = Logger.info("#{state.connection_id}: No known way to handle incoming data on stream id '#{stream.stream_id}' " <>
      "in state #{stream.current_state}.  Data: #{inspect data}")

    state
  end

  defp create_request(state, request) do
    request_id = state.last_request_id + 1
    state = %{state |
      last_request_id: request_id,
      active_requests: Map.put(state.active_requests, request_id, request)
    }

    {state, request_id}
  end

  defp accept_connect_request(state, app_name) do
    state = %{state |
      current_stage: :connected,
      connected_app_name: app_name
    }

    _ = Logger.debug("#{state.connection_id}: Accepted connection request for application '#{app_name}'")

    message = %Messages.Amf0Command{
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
        "objectEncoding" => state.specified_amf_version
      }]
    }

    :ok = send_output_message(state, message, 0)
    state
  end

  defp accept_publish_request(state, stream_id, stream_key) do
    active_stream = Map.fetch!(state.active_streams, stream_id)
    if active_stream.current_state != :created do
      message = "Attempted to accept publish request on stream id #{stream_id} that's in state '#{active_stream.current_state}'"
      raise("#{state.connection_id}: #{message}")
    end

    active_stream = %{active_stream |
      current_state: :publishing,
      stream_key: stream_key
    }

    state = %{state |
      active_streams: Map.put(state.active_streams, stream_id, active_stream)
    }

    response = %Messages.Amf0Command{
      command_name: "onStatus",
      transaction_id: 0,
      command_object: nil,
      additional_values: [%{
        "level" => "status",
        "code" => "NetStream.Publish.Start",
        "description" => "#{stream_key} is now published."
      }]
    }

    send_output_message(state, response, stream_id)
    state
  end

  defp accept_play_request(state, stream_id, stream_key, is_reset) do
    active_stream = Map.fetch!(state.active_streams, stream_id)
    if active_stream.current_state != :created do
      message = "Attempted to accept play request on stream id #{stream_id} that's in state '#{active_stream.current_state}'"
      raise("#{state.connection_id}: #{message}")
    end

    active_stream = %{active_stream |
      current_state: :playing,
      stream_key: stream_key
    }

    state = %{state |
      active_streams: Map.put(state.active_streams, stream_id, active_stream)
    }

    messages = [
      %Messages.UserControl{
        type: :stream_begin,
        stream_id: stream_id
      },
      %Messages.Amf0Command{
        command_name: "onStatus",
        transaction_id: 0,
        command_object: nil,
        additional_values: [%{
          "level" => "status",
          "code" => "NetStream.Play.Start",
          "description" => "Starting stream #{stream_key}"
        }]
      },
      %Messages.Amf0Data{parameters: ["|RtmpSampleAccess",false,false]},
      %Messages.Amf0Data{parameters: ["onStatus", %{"code" => "NetStream.Data.Start"}]},
    ]

    reset_message = %Messages.Amf0Command{
      command_name: "onStatus",
      transaction_id: 0,
      command_object: nil,
      additional_values: [%{
        "level" => "status",
        "code" => "NetStream.Play.Reset",
        "description" => "Reset for stream #{stream_key}"
      }]
    }

    messages = if is_reset, do: [reset_message | messages], else: messages
    send_output_message(state, messages, stream_id)
    state
  end

  defp send_output_message(state, messages, stream_id, force_uncompressed \\ false)

  defp send_output_message(_, [], _, _) do
    :ok
  end

  defp send_output_message(state, [message | rest], stream_id, force_uncompressed) do
    response = form_output_message(state, message, stream_id, force_uncompressed)
    :ok = state.protocol_handler_module.send_message(state.protocol_handler_pid, response)
    send_output_message(state, rest, stream_id, force_uncompressed)
  end

  defp send_output_message(state, message, stream_id, force_uncompressed) do
    send_output_message(state, [message], stream_id, force_uncompressed)
  end

  defp form_output_message(state, message_content, stream_id, force_uncompressed) do
    %DetailedMessage{
      timestamp: get_current_rtmp_epoch(state),
      stream_id: stream_id,
      content: message_content,
      force_uncompressed: force_uncompressed
    }
  end

  defp get_current_rtmp_epoch(state) do
    time_since_start = :os.system_time(:milli_seconds) - state.start_time
    Rtmp.Protocol.RtmpTime.to_rtmp_timestamp(time_since_start)
  end

  defp parse_play_other_args(args) do
    parse_play_other_args(:start_at, args, %PlayArguments{})
  end

  defp parse_play_other_args(_, [], results = %PlayArguments{}) do
    results
  end

  defp parse_play_other_args(:start_at, [value | rest], results = %PlayArguments{}) do
    results = %{results | start_at: value}
    parse_play_other_args(:duration, rest, results)
  end

  defp parse_play_other_args(:duration, [value | rest], results = %PlayArguments{}) do
    results = %{results | duration: value}
    parse_play_other_args(:reset, rest, results)
  end

  defp parse_play_other_args(:reset, [value | _], results = %PlayArguments{}) do
    results = %{results | is_reset: value}
    results
  end

  defp raise_event(_, []) do
    :ok
  end

  defp raise_event(state, [event | rest]) do
    :ok = state.event_receiver_module.send_event(state.event_receiver_pid, event)
    raise_event(state, rest)
  end

  defp raise_event(state, event) do
    raise_event(state, [event])
  end

  defp is_ignorable_command("_checkbw"), do: true
  defp is_ignorable_command(_), do: false
end