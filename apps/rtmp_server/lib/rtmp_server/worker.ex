defmodule RtmpServer.Worker do
  require Logger

  def start_link(args) do
    opts = Keyword.take(args, [:port])
    handler_options = Keyword.take(args, [:fms_version, :chunk_size])

    Logger.info "Starting RTMP listener on port #{Keyword.get(opts, :port)}"

    {:ok, _} = :ranch.start_listener(:RtmpServer, 100, :ranch_tcp, opts, RtmpServer.Handler, handler_options)
  end
end