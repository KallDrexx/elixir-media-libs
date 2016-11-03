defmodule SimpleRtmpServer.Worker do
  require Logger

  @behaviour GenRtmpServer

  def start_link() do
    options = %GenRtmpServer.RtmpOptions{}
    GenRtmpServer.start_link(__MODULE__, options)
  end

  def session_started(session_id, _client_ip) do
    _ = Logger.info "#{session_id}: simple rtmp server session started"  
  end
end