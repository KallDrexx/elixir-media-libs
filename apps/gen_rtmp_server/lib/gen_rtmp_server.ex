defmodule GenRtmpServer do
  @moduledoc """
  A behaviour module for implementing an RTMP server.

  A GenRtmpServer abstracts out the the handling of RTMP connection handling
  and data so that modules that implement this behaviour can focus on 
  the business logic of the actual RTMP events that are received and
  should be sent.
  """

  require Logger
                 
  @type session_id :: String.t
  @type client_ip :: String.t
  
  @callback session_started(session_id, client_ip) :: :ok
  
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
