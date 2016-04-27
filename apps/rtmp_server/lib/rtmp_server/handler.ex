defmodule RtmpServer.Handler do
  @moduledoc "Handles the rtmp socket connection"
  
  require Logger
  
  @doc "Starts the handler for an accepted socket"
  def start_link(ref, socket, transport, opts) do
    pid = spawn_link(__MODULE__, :init, [ref, socket, transport, opts])
    {:ok, pid}
  end
  
  def init(ref, socket, transport, _opts) do
    :ok = :ranch.accept_ack(ref)
    
    {:ok, {{ip1, ip2, ip3, ip4}, _port}} = :inet.peername(socket)
    client_ip = "#{ip1}.#{ip2}.#{ip3}.#{ip4}"
        
    Logger.info "#{client_ip}: client connected"
    
    case RtmpServer.Handshake.process(socket, transport) do
      {:error, reason} -> Logger.info "#{client_ip}: handshake failed (#{reason})"
      :ok -> Logger.debug "#{client_ip}: handshake successful"
    end
  end  
end