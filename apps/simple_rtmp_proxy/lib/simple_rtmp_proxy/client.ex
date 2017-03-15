defmodule SimpleRtmpProxy.Client do
  @behaviour GenRtmpClient

  alias Rtmp.ClientSession.Events, as: Events
  require Logger

  defmodule State do
    @moduledoc false

    defstruct status: :started,
              connection_info: nil,
              stream_key: nil,
              video_header: nil,
              audio_header: nil,
              metadata: nil,
              has_sent_keyframe: false
  end

  @spec relay_av_data(pid, Rtmp.ClientSession.Handler.av_type, Rtmp.timestamp, binary) :: :ok
  def relay_av_data(pid, type, timestamp, data) do
    _ = send(pid, {:relay_av, type, timestamp, data})
    :ok
  end

  def init(connection_info, [stream_key, video_header, audio_header, metadata]) do
    _ = Logger.debug("#{connection_info.connection_id}: client initialized for stream key #{stream_key}")
    state = %State{
      connection_info: connection_info,
      stream_key: stream_key,
      video_header: video_header,
      audio_header: audio_header,
      metadata: metadata
    }

    {:ok, state}
  end

  def handle_connection_response(%Events.ConnectionResponseReceived{was_accepted: true}, state) do
    _ = Logger.debug("#{state.connection_info.connection_id}: Connection accepted, requesting publishing")

    GenRtmpClient.start_publish(self(), state.stream_key, :live)

    state = %{state | status: :connected}
    {:ok, state}
  end

  def handle_play_response(_respponse, state) do
    raise("#{state.connection_info.connection_id}: Received playback response but playback should have never been requested")
  end

  def handle_play_reset(_event, state) do
    raise("#{state.connection_info.connection_id}: Received play reset command but playback isn't expected'")
  end

  def handle_metadata_received(_metadata, state) do
    _ = Logger.warn("#{state.connection_info.connection_id}: Metadata received unexpectedly")
    {:ok, state}
  end

  def handle_av_data_received(_av_message, state) do
    _ = Logger.warn("#{state.connection_info.connection_id}: AV data received unexpectedly")

    {:ok, state}
  end

  def handle_publish_response(event = %Events.PublishResponseReceived{was_accepted: true}, state) do
    _ = Logger.debug("#{state.connection_info.connection_id}: Publish accepted for stream key #{event.stream_key}")

    :ok = GenRtmpClient.publish_metadata(self(), state.stream_key, state.metadata)
    :ok = GenRtmpClient.publish_av_data(self(), state.stream_key, :audio, 0, state.audio_header)
    :ok = GenRtmpClient.publish_av_data(self(), state.stream_key, :video, 0, state.video_header)

    state = %{state | status: :publishing}
    {:ok, state}
  end

  def handle_disconnection(reason, state) do
    _ = Logger.debug("#{state.connection_info.connection_id}: Disconnected - #{inspect(reason)}")

    case reason do
      :stopping -> {:stop, state}
      _ -> {:retry, state}
    end
  end

  def byte_io_totals_updated(_event, state) do
    {:ok, state}
  end

  def handle_message({:relay_av, type, timestamp, data}, state = %State{status: :publishing}) do
    should_relay_data = case {state.has_sent_keyframe, type, is_keyframe(data)} do
      {true, _, _} -> true
      {false, :video, true} -> true
      {false, _, _} -> false
    end

    state = case should_relay_data do
      false -> state

      true ->
        :ok = GenRtmpClient.publish_av_data(self(), state.stream_key, type, timestamp, data)
        %{state | has_sent_keyframe: true}      
    end

    {:ok, state}
  end

  def handle_message({:relay_av, _type, _timestamp, _data}, state) do
    # ignore since we aren't publishing
    {:ok, state}
  end

  def handle_message(message, state) do
    _ = Logger.debug("#{state.connection_info.connection_id}: Unknown message received: #{inspect(message)}")

    {:ok, state}
  end

  defp is_keyframe(<<0x17, _::binary>>), do: true
  defp is_keyframe(_), do: false
end