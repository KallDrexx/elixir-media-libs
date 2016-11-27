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
              stream_id: nil
  end

  def start_link() do
    options = %GenRtmpServer.RtmpOptions{}
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

  def publish_requested(%RtmpEvents.PublishStreamRequested{}, state = %State{}) do
    {:accepted, state}
  end

  def publish_finished(%RtmpEvents.PublishingFinished{}, state = %State{}) do
    {:ok, state}
  end

  def play_requested(event = %RtmpEvents.PlayStreamRequested{}, state = %State{}) do
    activity_key = generate_activity_key(event.app_name, event.stream_key)
    case Map.fetch(state.activities, activity_key) do
      {:ok, activity} ->
        # Activity already exists, error if we are publishing on the same
        # application and stream key that we are trying to publish for
        if activity.type != :publishing do
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

  def metadata_received(%RtmpEvents.StreamMetaDataChanged{}, state = %State{}) do
    {:ok, state}
  end

  def audio_video_data_received(event = %RtmpEvents.AudioVideoDataReceived{}, state = %State{}) do
    activity_key = generate_activity_key(event.app_name, event.stream_key)

    :pg2.create(activity_key)
    player_processes = :pg2.get_members(activity_key)
    :ok = send_to_processes(player_processes, {:av_data, event})

    {:ok, state}
  end

  def handle_message({:av_data, event = %RtmpEvents.AudioVideoDataReceived{}}, state = %State{}) do
    activity_key = generate_activity_key(event.app_name, event.stream_key)
    {:ok, activity} = Map.fetch(state.activities, activity_key)

    outbound_message = %GenRtmpServer.AudioVideoData{
      data_type: event.data_type,
      data: event.data
    }

    GenRtmpServer.send_message(self(), outbound_message, activity.stream_id)
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

  defp send_to_processes([], _message) do
    :ok
  end

  defp send_to_processes([pid | rest], message) do
    send(pid, message)
    send_to_processes(rest, message)
  end
end