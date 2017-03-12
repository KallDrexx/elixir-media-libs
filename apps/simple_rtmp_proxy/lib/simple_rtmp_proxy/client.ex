defmodule SimpleRtmpProxy.Client do
  @behaviour GenRtmpClient

  alias Rtmp.ClientSession.Events, as: Events
  require Logger

  defmodule State do
    @moduledoc false

    defstruct status: :started,
              connection_info: nil,
              stream_key: nil
  end

  def init(connection_info, stream_key) do
    _ = Logger.debug("#{connection_info.connection_id}: client initialized for stream key #{stream_key}")
    state = %State{
      connection_info: connection_info,
      stream_key: stream_key
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
end