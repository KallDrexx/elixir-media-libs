defmodule SimpleRtmpPlayer.Client do
  @behaviour GenRtmpClient

  alias Rtmp.ClientSession.Events, as: Events

  require Logger

  defmodule State do
    defstruct status: :started,
              connection_info: nil,
              stream_key: nil,
              av_bytes_received: 0,
              last_av_announcement: 0
  end

  def init(connection_info, stream_key) do
    _ = Logger.debug("Initialized: #{inspect(connection_info)} with stream key: #{stream_key}")
    state = %State{connection_info: connection_info, stream_key: stream_key}
    {:ok, state}
  end

  def handle_connection_response(%Events.ConnectionResponseReceived{was_accepted: true}, state) do
    _ = Logger.debug("Connection accepted, requesting playback on stream key")

    GenRtmpClient.start_playback(self(), state.stream_key)

    state = %{state | status: :connected}
    {:ok, state}
  end

  def handle_play_response(response, state) do
    _ = Logger.debug("Play response received: #{inspect(response)}")
    {:ok, state}
  end

  def handle_play_reset(event = %Events.PlayResetReceived{}, state) do
    _ = Logger.debug("Play reset received: #{event.description}")
    {:ok, state}
  end

  def handle_publish_response(response, state) do
    _ = Logger.debug("Publish response received: #{inspect(response)}")
    {:ok, state}
  end

  def handle_metadata_received(metadata, state) do
    _ = Logger.debug("Metadata received: #{inspect(metadata)}")
    {:ok, state}
  end

  def handle_av_data_received(av_message, state) do
    state = %{state | av_bytes_received: state.av_bytes_received + byte_size(av_message.data)}
    state = cond do
      state.av_bytes_received - state.last_av_announcement > 10_1000 ->
        _ = Logger.debug("Received #{state.av_bytes_received} bytes of a/v data")
        %{state | last_av_announcement: state.av_bytes_received}

      true -> state
    end

    {:ok, state}
  end

  def handle_disconnection(reason, state) do
    _ = Logger.debug("Disconnected: #{inspect(reason)}")
    {:stop, state}
  end

  def byte_io_totals_updated(event, state) do
    _ = Logger.debug("IO totals updated: #{inspect(event)}")
    {:ok, state}
  end

  def handle_message(message, state) do
    _ = Logger.warn("#{state.connection_info.connection_id}: Unable to handle client message: #{message}")
    {:ok, state}
  end

end