defmodule SimpleRtmpServer.Worker do
  @moduledoc """
  Simple implementation of an RTMP server utilizing the `GenRtmpServer` behaviour.

  This server allows publishing and playing data on any application and stream key.
  This is a dumb implmenetation and thus no care is done to prevent two users from
  publishing on the same stream key, or trying to play content on a stream key not being published to.
  """

  alias RtmpSession.Events, as: RtmpEvents
  require Logger

  @behaviour GenRtmpServer

  defmodule State do
    defstruct session_id: nil,
              client_ip: nil,
              activities: %{}
  end

  defmodule Activity do
    defstruct type: nil, # publishing or playing
              app_name: nil,
              stream_key: nil,
              stream_id: nil,
              last_metadata_event: nil,
              has_sent_keyframe: false,
              sequence_header_event: nil
  end

  def start_link() do
    options = %GenRtmpServer.RtmpOptions{log_mode: :none}
    GenRtmpServer.start_link(__MODULE__, options)
  end

  def init(session_id, client_ip) do
    _ = Logger.info "#{session_id}: simple rtmp server session started"

    state = %State{
      session_id: session_id,
      client_ip: client_ip
    } 

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

        Logger.warn("#{state.session_id}: Duplicate publishing request for application '#{event.app_name}' " <>
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
        :pg2.join(publisher_key, self())
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

        :pg2.leave(publisher_key, self())
        activities = Map.delete(state.activities, activity_key)
        state = %{state | activities: activities}
        {:ok, state}

      :error ->
        Logger.warn("#{state.session_id}: Attempted to stop publishing for application '#{event.app_name}' " <>
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

        Logger.warn("#{state.session_id}: Duplicate play request for application '#{event.app_name}' " <>
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
        :pg2.join(activity_key, self())
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

        :pg2.leave(activity_key, self())
        activities = Map.delete(state.activities, activity_key)
        state = %{state | activities: activities}
        {:ok, state}

      :error ->
        Logger.warn("#{state.session_id}: Attempted to stop playing for application '#{event.app_name}' " <>
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

    state = case is_sequence_header(event.data) do
      true ->
        activity = Map.fetch!(state.activities, activity_key)
        activity = %{activity | sequence_header_event: event}
        activities = Map.put(state.activities, activity_key, activity)
        %{state | activities: activities}

      false -> state
    end

    :pg2.create(activity_key)
    player_processes = :pg2.get_members(activity_key)
    :ok = send_to_processes(player_processes, {:av_data, event})

    {:ok, state}
  end

  def handle_message({:av_data, event = %RtmpEvents.AudioVideoDataReceived{}}, state = %State{}) do
    activity_key = generate_activity_key(event.app_name, event.stream_key)
    {:ok, activity} = Map.fetch(state.activities, activity_key)

    should_send_message = case {activity.has_sent_keyframe, is_keyframe(event.data)} do
      {true, _} -> true
      {false, true} -> true
      _ -> false
    end

    state = if should_send_message do
        outbound_message = %GenRtmpServer.AudioVideoData{
        data_type: event.data_type,
        data: event.data,
        received_at_timestamp: event.received_at_timestamp
      }

      stream_id = activity.stream_id

      state = case activity.has_sent_keyframe do
        true -> state
        false ->
          send_sequence_header(activity.sequence_header_event, event.received_at_timestamp, activity.stream_id)
          activity = %{activity | has_sent_keyframe: true}
          activities = Map.put(state.activities, activity_key, activity)
          %{state | activities: activities}
      end

      GenRtmpServer.send_message(self(), outbound_message, stream_id, event.timestamp)
      state
    else
      state
    end

    {:ok, state}
  end

  def handle_message({:metadata, event = %RtmpEvents.StreamMetaDataChanged{}}, state = %State{}) do
    activity_key = generate_activity_key(event.app_name, event.stream_key)
    {:ok, activity} = Map.fetch(state.activities, activity_key)

    outbound_message = %GenRtmpServer.MetaData{
      details: event.meta_data
    }

    GenRtmpServer.send_message(self(), outbound_message, activity.stream_id)
    {:ok, state}
  end

  def handle_message({:sequence_header, event = %RtmpEvents.AudioVideoDataReceived{}}, state = %State{}) do
    activity_key = generate_activity_key(event.app_name, event.stream_key)
    {:ok, activity} = Map.fetch(state.activities, activity_key)

    activity = %{activity | sequence_header_event: event}
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
        if activity.sequence_header_event != nil do
          :pg2.create(activity_key)
          player_processes = :pg2.get_members(activity_key)
          :ok = send_to_processes(player_processes, {:sequence_header, activity.sequence_header_event})
        end

        {:ok, state}

      :error -> {:ok, state}
    end
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

  defp is_sequence_header(<<0x17, 0x00, _::binary>>), do: true
  defp is_sequence_header(_), do: false

  defp send_sequence_header(nil, _, _) do
    :ok
  end

  defp send_sequence_header(event = %RtmpEvents.AudioVideoDataReceived{}, forced_timestamp, stream_id) do
    outbound_message = %GenRtmpServer.AudioVideoData{
      data_type: event.data_type,
      data: event.data,
      received_at_timestamp: forced_timestamp
    }

    Logger.debug("Sending sequence header")
    GenRtmpServer.send_message(self(), outbound_message, stream_id)
  end
end