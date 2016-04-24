defmodule RtmpServer.Worker do
  def start_link do
    opts = [port: 1935]
    {:ok, _} = :ranch.start_listener(:RtmpServer, 100, :ranch_tcp, opts, RtmpServer.Handler, [])
  end
end