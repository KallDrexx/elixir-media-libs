defmodule SimpleRtmpServer.Worker do
  @moduledoc """
  Simple implementation of an RTMP server utilizing the `GenRtmpServer` behaviour.

  This server allows publishing and playing data on any application and stream key.
  This is a dumb implmenetation and thus no care is done to prevent two users from
  publishing on the same stream key, or trying to play content on a stream key not being published to.
  """

  alias Rtmp.ServerSession.Events, as: RtmpEvents
  require Logger

  @behaviour GenRtmpServer

  defmodule State do
    defstruct session_id: nil,
              client_ip: nil,
              activities: %{},
              bytes_received: 0,
              bytes_sent: 0,
              last_ping_request_timestamp: 0
  end

  defmodule Activity do
    defstruct type: nil, # publishing or playing
              app_name: nil,
              stream_key: nil,
              stream_id: nil,
              last_metadata_event: nil,
              has_sent_keyframe: false,
              video_sequence_header_event: nil,
              audio_sequence_header_event: nil,
              has_sent_audio_header: false
  end

  def start_link() do
    options = %GenRtmpServer.RtmpOptions{log_mode: :none}
    GenRtmpServer.start_link(__MODULE__, options)
  end

  def init(session_id, client_ip, _args) do
    _ = Logger.info "#{session_id}: simple rtmp server session started"

    state = %State{
      session_id: session_id,
      client_ip: client_ip
    }

    :erlang.send_after(1000 * 60, self(), :trigger_rtmp_request)
    {:ok, state}
  end

  def connection_requested(%RtmpEvents.ConnectionRequested{}, state = %State{}) do
    {:accepted, state}
  end

  def publish_requested(event = %RtmpEvents.PublishStreamRequested{}, state = %State{}) do
    activity_key = generate_activity_key(event.app_name, event.stream_key)
    publisher_key = generate_publisher_group_name(event.app_name, event.stream_key)
    case Map.fetch(state.activities, activity_key) do
      {:ok, activity} ->
        # Activity already exists, error if we are playing on the same
        # application and stream key that we are trying to publish on
        if activity.type != :publishing do
          message = "#{state.session_id}: Attempted to publish on application (#{event.app_name}) " <>
            "and stream key (#{event.stream_key}) that's already active with type #{activity.type}"

          raise(message)
        end

        _ = Logger.warn("#{state.session_id}: Duplicate publishing request for application '#{event.app_name}' " <>
            "and stream key '#{event.stream_key}'")

        {:accepted, state}

      :error ->
        # Start this activity
        activity = %Activity{
          type: :publishing,
          app_name: event.app_name,
          stream_key: event.stream_key,
          stream_id: event.stream_id
        }

        :pg2.create(publisher_key)
        :ok = :pg2.join(publisher_key, self())
        activities = Map.put(state.activities, activity_key, activity)
        state = %{state | activities: activities}

        {:accepted, state}
    end
  end

  def publish_finished(event = %RtmpEvents.PublishingFinished{}, state = %State{}) do
    activity_key = generate_activity_key(event.app_name, event.stream_key)
    publisher_key = generate_publisher_group_name(event.app_name, event.stream_key)
    case Map.fetch(state.activities, activity_key) do
      {:ok, activity} ->
        if activity.type != :publishing do
          message = "#{state.session_id}: Attempted to stop publishing on application (#{event.app_name}) " <>
            "and stream key (#{event.stream_key}) that's active with type #{activity.type}"

            raise(message)
        end

        :ok = :pg2.leave(publisher_key, self())
        activities = Map.delete(state.activities, activity_key)
        state = %{state | activities: activities}
        {:ok, state}

      :error ->
        _ = Logger.warn("#{state.session_id}: Attempted to stop publishing for application '#{event.app_name}' " <>
            "and stream key '#{event.stream_key}' but no publish activity was found")
        {:ok, state}
    end
  end

  def play_requested(event = %RtmpEvents.PlayStreamRequested{}, state = %State{}) do
    activity_key = generate_activity_key(event.app_name, event.stream_key)
    case Map.fetch(state.activities, activity_key) do
      {:ok, activity} ->
        # Activity already exists, error if we are publishing on the same
        # application and stream key that we are trying to play for
        if activity.type != :playing do
          message = "#{state.session_id}: Attempted to play on application (#{event.app_name}) " <>
            "and stream key (#{event.stream_key}) that's already active with type #{activity.type}"

          raise(message)
        end

        _ = Logger.warn("#{state.session_id}: Duplicate play request for application '#{event.app_name}' " <>
            "and stream key '#{event.stream_key}'")

        {:accepted, state}

      :error ->
        # Start this activity
        activity = %Activity{
          type: :playing,
          app_name: event.app_name,
          stream_key: event.stream_key,
          stream_id: event.stream_id
        }

        :pg2.create(activity_key)
        :ok = :pg2.join(activity_key, self())
        activities = Map.put(state.activities, activity_key, activity)
        state = %{state | activities: activities}

        publisher_key = generate_publisher_group_name(event.app_name, event.stream_key)
        :pg2.create(publisher_key)
        publisher_processes = :pg2.get_members(publisher_key)
        :ok = send_to_processes(publisher_processes, {:metadata_request, event.app_name, event.stream_key})
        :ok = send_to_processes(publisher_processes, {:sequence_header_request, event.app_name, event.stream_key})

        {:accepted, state}
    end
  end

  def play_finished(event = %RtmpEvents.PlayStreamFinished{}, state = %State{}) do
    activity_key = generate_activity_key(event.app_name, event.stream_key)
    case Map.fetch(state.activities, activity_key) do
      {:ok, activity} ->
        if activity.type != :playing do
          message = "#{state.session_id}: Attempted to stop playing on application (#{event.app_name}) " <>
            "and stream key (#{event.stream_key}) that's active with type #{activity.type}"

            raise(message)
        end

        :ok = :pg2.leave(activity_key, self())
        activities = Map.delete(state.activities, activity_key)
        state = %{state | activities: activities}
        {:ok, state}

      :error ->
        _ = Logger.warn("#{state.session_id}: Attempted to stop playing for application '#{event.app_name}' " <>
            "and stream key '#{event.stream_key}' but no publish activity was found")
        {:ok, state}
    end
  end

  def metadata_received(event = %RtmpEvents.StreamMetaDataChanged{}, state = %State{}) do
    activity_key = generate_activity_key(event.app_name, event.stream_key)

    :pg2.create(activity_key)
    player_processes = :pg2.get_members(activity_key)
    :ok = send_to_processes(player_processes, {:metadata, event})

    activity = Map.fetch!(state.activities, activity_key)
    activity = %{activity | last_metadata_event: event}
    activities = Map.put(state.activities, activity_key, activity)
    state = %{state | activities: activities}

    {:ok, state}
  end

  def audio_video_data_received(event = %RtmpEvents.AudioVideoDataReceived{}, state = %State{}) do
    activity_key = generate_activity_key(event.app_name, event.stream_key)

    state = case event.data_type == :video && is_video_sequence_header(event.data) do
      true ->
        activity = Map.fetch!(state.activities, activity_key)
        activity = %{activity | video_sequence_header_event: event}
        activities = Map.put(state.activities, activity_key, activity)
        %{state | activities: activities}

      false -> state
    end

    state = case event.data_type == :audio && is_audio_sequence_header(event.data) do
      true ->
        activity = Map.fetch!(state.activities, activity_key)
        activity = %{activity | audio_sequence_header_event: event}
        activities = Map.put(state.activities, activity_key, activity)
        %{state | activities: activities}

      false -> state
    end

    :pg2.create(activity_key)
    player_processes = :pg2.get_members(activity_key)
    :ok = send_to_processes(player_processes, {:av_data, event})

    {:ok, state}
  end

  def acknowledgement_received(event = %RtmpEvents.AcknowledgementReceived{}, state) do
    # More complicated rtmp servers should track these and make sure the client doesn't
    # go too long without sending an ack.  For the simple server we don't really care.
    Logger.debug("#{state.session_id}: Acknowledgement received: #{event.bytes_received}")
    {:ok, state}
  end

  def byte_io_totals_updated(event = %RtmpEvents.NewByteIOTotals{}, state = %State{}) do
    state = %{state |
      bytes_sent: event.bytes_sent,
      bytes_received: event.bytes_received
    }

    {:ok, state}
  end

  def ping_request_sent(%RtmpEvents.PingRequestSent{}, state = %State{}) do
    state = %{state | last_ping_request_timestamp: :os.system_time(:milli_seconds)}
    {:ok, state}
  end

  def ping_response_received(%RtmpEvents.PingResponseReceived{}, state) do
    latency = :os.system_time(:milli_seconds) - state.last_ping_request_timestamp
    _ = Logger.debug("#{state.session_id}: Ping response received (latency #{latency}ms)")

    {:ok, state}
  end

  def handle_message({:av_data, event = %RtmpEvents.AudioVideoDataReceived{}}, state = %State{}) do
    activity_key = generate_activity_key(event.app_name, event.stream_key)

    state = case Map.fetch(state.activities, activity_key) do
      :error ->
        # race condition, AV data sent while activity was being closed.  Can be ignored I believe
        state

      {:ok, activity} ->
        should_send_message = case {activity.has_sent_keyframe, is_keyframe(event.data)} do
          {true, _} -> true
          {false, true} -> true
          _ -> false
        end

        if should_send_message, do: send_message(state, event, activity, activity_key), else: state
    end

    {:ok, state}
  end

  def handle_message({:metadata, event = %RtmpEvents.StreamMetaDataChanged{}}, state = %State{}) do
    activity_key = generate_activity_key(event.app_name, event.stream_key)
    {:ok, activity} = Map.fetch(state.activities, activity_key)

    outbound_message = %GenRtmpServer.MetaData{
      details: event.meta_data
    }

    GenRtmpServer.send_message(self(), outbound_message, activity.stream_id, nil)
    {:ok, state}
  end

  def handle_message({:sequence_header, event = %RtmpEvents.AudioVideoDataReceived{}}, state = %State{}) do
    activity_key = generate_activity_key(event.app_name, event.stream_key)
    {:ok, activity} = Map.fetch(state.activities, activity_key)

    activity = case event.data_type do
      :video -> %{activity | video_sequence_header_event: event}
      :audio -> %{activity | audio_sequence_header_event: event}
    end

    activities = Map.put(state.activities, activity_key, activity)
    state = %{state | activities: activities}

    {:ok, state}
  end

  def handle_message({:metadata_request, app_name, stream_key}, state = %State{}) do
    activity_key = generate_activity_key(app_name, stream_key)
    case Map.fetch(state.activities, activity_key) do
      {:ok, activity} ->
        if activity.last_metadata_event != nil do
          :pg2.create(activity_key)
          player_processes = :pg2.get_members(activity_key)
          :ok = send_to_processes(player_processes, {:metadata, activity.last_metadata_event})
        end

        {:ok, state}

      :error -> {:ok, state}
    end
  end

  def handle_message({:sequence_header_request, app_name, stream_key}, state = %State{}) do
    activity_key = generate_activity_key(app_name, stream_key)
    case Map.fetch(state.activities, activity_key) do
      {:ok, activity} ->
        if activity.video_sequence_header_event != nil do
          :pg2.create(activity_key)
          player_processes = :pg2.get_members(activity_key)
          :ok = send_to_processes(player_processes, {:sequence_header, activity.video_sequence_header_event})
        end

        if activity.audio_sequence_header_event != nil do
          :pg2.create(activity_key)
          player_processes = :pg2.get_members(activity_key)
          :ok = send_to_processes(player_processes, {:sequence_header, activity.audio_sequence_header_event})
        end

        {:ok, state}

      :error -> {:ok, state}
    end
  end

  def handle_message(:trigger_rtmp_request, state = %State{}) do
    GenRtmpServer.send_ping_request(self())
    :erlang.send_after(1000 * 60, self(), :trigger_rtmp_request)
    {:ok, state}
  end

  def handle_message(message, state = %State{}) do
    _ = Logger.debug("#{state.session_id}: Unknown message received: #{inspect(message)}")
    {:ok, state}
  end

  def code_change(_, state = %State{}) do
    {:ok, state}
  end

  defp generate_activity_key(app_name, stream_key) do
    app_name <> "__" <> stream_key
  end

  defp generate_publisher_group_name(app_name, stream_key) do
    app_name <> "__" <> stream_key <> "__publisher"
  end

  defp send_to_processes([], _message) do
    :ok
  end

  defp send_to_processes([pid | rest], message) do
    send(pid, message)
    send_to_processes(rest, message)
  end

  defp is_keyframe(<<0x17, _::binary>>), do: true
  defp is_keyframe(_), do: false

  defp is_video_sequence_header(<<0x17, 0x00, _::binary>>), do: true
  defp is_video_sequence_header(_), do: false

  defp is_audio_sequence_header(<<0xaf, 0x00, _::binary>>), do: true
  defp is_audio_sequence_header(_), do: false

  defp send_sequence_header(nil, _, _, _) do
    :ok
  end

  defp send_sequence_header(event = %RtmpEvents.AudioVideoDataReceived{}, forced_timestamp, stream_id, state) do
    outbound_message = %GenRtmpServer.AudioVideoData{
      data_type: event.data_type,
      data: event.data,
      received_at_timestamp: forced_timestamp
    }

    _ = Logger.debug("#{state.session_id}: Sending #{event.data_type} sequence header")
    GenRtmpServer.send_message(self(), outbound_message, stream_id)
  end

  defp send_message(state, event = %RtmpEvents.AudioVideoDataReceived{data_type: :video}, activity, activity_key) do
    outbound_message = %GenRtmpServer.AudioVideoData{
      data_type: event.data_type,
      data: event.data,
      received_at_timestamp: event.received_at_timestamp
    }

    stream_id = activity.stream_id

    state = case activity.has_sent_keyframe do
      true -> state
      false ->
        send_sequence_header(activity.video_sequence_header_event, event.received_at_timestamp, activity.stream_id, state)
        activity = %{activity | has_sent_keyframe: true}
        activities = Map.put(state.activities, activity_key, activity)
        %{state | activities: activities}
    end

    GenRtmpServer.send_message(self(), outbound_message, stream_id, event.timestamp)
    state
  end

  defp send_message(state, event = %RtmpEvents.AudioVideoDataReceived{data_type: :audio}, activity, activity_key) do
    outbound_message = %GenRtmpServer.AudioVideoData{
      data_type: event.data_type,
      data: event.data,
      received_at_timestamp: event.received_at_timestamp
    }

    stream_id = activity.stream_id
    state = case activity.has_sent_audio_header do
      true -> state
      false ->
        send_sequence_header(activity.audio_sequence_header_event, event.received_at_timestamp, activity.stream_id, state)
        activity = %{activity | has_sent_audio_header: true}
        activities = Map.put(state.activities, activity_key, activity)
        %{state | activities: activities}
    end

    GenRtmpServer.send_message(self(), outbound_message, stream_id, event.timestamp)
    state
  end

end