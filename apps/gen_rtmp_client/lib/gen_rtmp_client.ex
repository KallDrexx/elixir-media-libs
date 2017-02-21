defmodule GenRtmpClient do
  @moduledoc """
  A behaviour for creating RTMP clients.

  A `GenRtmpClient` abstracts out the functionality and RTMP message flow
  so that modules that implement this behaviour can focus on the high level
  business logic of how their RTMP client should behave. 
  """

  alias Rtmp.ClientSession.Events, as: SessionEvents
  
  @type adopter_module :: module
  @type adopter_state :: any
  @type adopter_response :: {:ok, adopter_state}

  @callback handle_initialization(SessionEvents.ConnectionResponseReceived.t) :: {:ok, adopter_state}
  @callback handle_connection_response(SessionEvents.ConnectionResponseReceived.t, adopter_state) :: adopter_response
  @callback handle_play_response(SessionEvents.PlayResponseReceived.t, adopter_state) :: adopter_response
  @callback handle_publish_response(SessionEvents.PublishResponseReceived.t, adopter_state) :: adopter_response
  @callback handle_metadata_received(SessionEvents.StreamMetaDataReceived.t, adopter_state) :: adopter_response
  @callback handle_av_data_received(SessionEvents.AudioVideoDataReceived.t, adopter_state) :: adopter_response

  @callback handle_disconnection(adopter_state) :: {:stop, adopter_state} | {:reconnect, adopter_state}

  @spec start_link(adopter_module, GenRtmpClient.ConnectionInfo.t) :: Supervisor.on_start
  @spec disconnect(pid) :: :ok
  @spec start_playback(pid, Rtmp.stream_key) :: :ok
  @spec stop_playback(pid, Rtmp.stream_key) :: :ok
  @spec start_publish(pid, Rtmp.stream_key, Rtmp.ClientSession.Handler.publish_type) :: :ok
  @spec stop_publish(pid, Rtmp.stream_key) :: :ok
  @spec publish_metadata(pid, Rtmp.Stream_key, Rtmp.StreamMetadata.t) :: :ok
  @spec publis_av_data(pid, Rtmp.stream_key, Rtmp.ClientSession.Handler.av_type, Rtmp.timestamp, binary) :: :ok

end
