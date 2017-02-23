defmodule SimpleRtmpPlayer.Client do
  @behaviour GenRtmpClient

  require Logger

  defmodule State do
    defstruct status: :started,
              connection_info: nil
  end

  def init(connection_info) do
    _ = Logger.debug("Initialized: #{inspect(connection_info)}")
    state = %State{connection_info: connection_info}
    {:ok, state}
  end

  def handle_connection_response(response, state) do
    _ = Logger.debug("Connection response received: #{inspect(response)}")
    {:ok, state}
  end

  def handle_play_response(response, state) do
    _ = Logger.debug("Play response received: #{inspect(response)}")
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

  def handle_av_data_received(av_data, state) do
    _ = Logger.debug("AV received: #{inspect(av_data)}")
    {:ok, state}
  end

  def handle_disconnection(state) do
    _ = Logger.debug("Disconnected")
    {:stop, state}
  end

end