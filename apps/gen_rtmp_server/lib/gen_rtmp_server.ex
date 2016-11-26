defmodule GenRtmpServer do
  @moduledoc """
  A behaviour module for implementing an RTMP server.

  A GenRtmpServer abstracts out the the handling of RTMP connection handling
  and data so that modules that implement this behaviour can focus on 
  the business logic of the actual RTMP events that are received and
  should be sent.
  """

  alias RtmpSession.Events, as: RtmpEvents
  require Logger
                 
  @type session_id :: String.t
  @type client_ip :: String.t
  @type adopter_state :: any
  @type command :: :ignore | :disconnect
  @type request_result :: :accepted | {:rejected, command, String.t}
  
  @callback init(session_id, client_ip) :: {:ok, adopter_state}
  @callback connection_requested(RtmpEvents.ConnectionRequested.t, adopter_state)
    :: {request_result, adopter_state}

  @callback publish_requested(RtmpEvents.PublishStreamRequested.t, adopter_state)
    :: {request_result, adopter_state}

  @callback publish_finished(RtmpEvents.PublishingFinished.t, adopter_state)
    :: {:ok, adopter_state}

  @callback play_requested(RtmpEvents.PlayStreamRequested.t, adopter_state)
    :: {request_result, adopter_state}

  @callback play_finished(RtmpEvents.PlayStreamFinished.t, adopter_state)
    :: {:ok, adopter_state}

  @callback metadata_received(RtmpEvents.StreamMetaDataChanged.t, adopter_state)
    :: {:ok, adopter_state}

  @callback audio_video_data_received(RtmpEvents.AudioVideoDataReceived.t, adopter_state)
    :: {:ok, adopter_state}
  
  @spec start_link(module(), %GenRtmpServer.RtmpOptions{}) :: Supervisor.on_start
  def start_link(module, options = %GenRtmpServer.RtmpOptions{}) do
    {:ok, _} = Application.ensure_all_started(:ranch)

    _ = Logger.info "Starting RTMP listener on port #{options.port}"

    :ranch.start_listener(module, 
                          10, 
                          :ranch_tcp, 
                          [port: options.port],
                          GenRtmpServer.Protocol,
                          [module, options])

    
  end

end
