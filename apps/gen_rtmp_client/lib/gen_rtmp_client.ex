defmodule GenRtmpClient do
  @moduledoc """
  A behaviour for creating RTMP clients.

  A `GenRtmpClient` abstracts out the functionality and RTMP message flow
  so that modules that implement this behaviour can focus on the high level
  business logic of how their RTMP client should behave. 
  """

  use GenServer

  alias Rtmp.ClientSession.Events, as: SessionEvents
  
  @type adopter_module :: module
  @type adopter_state :: any
  @type adopter_args :: any
  @type adopter_response :: {:ok, adopter_state}
  @type rtmp_client_pid :: pid

  @callback init(GenRtmpClient.ConnectionInfo.t, adopter_args) :: {:ok, adopter_state}
  @callback handle_connection_response(SessionEvents.ConnectionResponseReceived.t, adopter_state) :: adopter_response
  @callback handle_play_response(SessionEvents.PlayResponseReceived.t, adopter_state) :: adopter_response
  @callback handle_publish_response(SessionEvents.PublishResponseReceived.t, adopter_state) :: adopter_response
  @callback handle_metadata_received(SessionEvents.StreamMetaDataReceived.t, adopter_state) :: adopter_response
  @callback handle_av_data_received(SessionEvents.AudioVideoDataReceived.t, adopter_state) :: adopter_response
  @callback handle_disconnection(adopter_state) :: {:stop, adopter_state} | {:reconnect, adopter_state}

  defmodule State do
    @moduledoc false

    defstruct adopter_module: nil,
              adopter_state: nil,
              connection_info: nil
  end

  @spec start_link(adopter_module, GenRtmpClient.ConnectionInfo.t, adopter_args) :: GenServer.on_start
  @doc """
  Starts a new RTMP connection to the specified server.  The client's logic is managed by the module
  specified by the adopter_module, which is expected to adopt the `GenRtmpClient` behaviour.
  """
  def start_link(adopter_module, connection_info = %GenRtmpClient.ConnectionInfo{}, adopter_args) do
    GenServer.start_link(__MODULE__, [adopter_module, connection_info, adopter_args])
  end

  @spec disconnect(rtmp_client_pid) :: :ok
  def disconnect(rtmp_client_pid) do
    GenServer.cast(rtmp_client_pid, :disconnect)
  end

  @spec start_playback(rtmp_client_pid, Rtmp.stream_key) :: :ok
  def start_playback(rtmp_client_pid, stream_key) do
    GenServer.cast(rtmp_client_pid, {:start_playback, stream_key})
  end

  @spec stop_playback(rtmp_client_pid, Rtmp.stream_key) :: :ok
  def stop_playback(rtmp_client_pid, stream_key) do
    GenServer.cast(rtmp_client_pid, {:stop_playback, stream_key})
  end

  @spec start_publish(rtmp_client_pid, Rtmp.stream_key, Rtmp.ClientSession.Handler.publish_type) :: :ok
  def start_publish(rtmp_client_pid, stream_key, type) do
    GenServer.cast(rtmp_client_pid, {:start_publish, stream_key, type})
  end

  @spec stop_publish(rtmp_client_pid, Rtmp.stream_key) :: :ok
  def stop_publish(rtmp_client_pid, stream_key) do
    GenServer.cast(rtmp_client_pid, {:stop_publish, stream_key})
  end

  @spec publish_metadata(rtmp_client_pid, Rtmp.stream_key, Rtmp.StreamMetadata.t) :: :ok
  def publish_metadata(rtmp_client_pid, stream_key, metadata) do
    GenServer.cast(rtmp_client_pid, {:publish_metadata, stream_key, metadata})
  end

  @spec publish_av_data(rtmp_client_pid, Rtmp.stream_key, Rtmp.ClientSession.Handler.av_type, Rtmp.timestamp, binary) :: :ok
  def publish_av_data(rtmp_client_pid, stream_key, type, timestamp, data) do
    GenServer.cast(rtmp_client_pid, {:publish_av_data, stream_key, type, timestamp, data})
  end

  def init([adopter_module, connection_info, adopter_args]) do
    IO.puts("Started client #{connection_info.connection_id}")
    adopter_state = adopter_module.init(connection_info, adopter_args)

    {:ok, %State{
      adopter_module: adopter_module,
      adopter_state: adopter_state,
      connection_info: connection_info
    }}
  end
end
