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
    
    {:ok, {ip, _port}} = :inet.peername(socket)
    client_ip_string = ip |> Tuple.to_list() |> Enum.join(".")
        
    Logger.info "#{client_ip_string}: client connected"
    
    case RtmpServer.Handshake.process(socket, transport) do
      {:error, reason} -> Logger.info "#{client_ip_string}: handshake failed (#{reason})"
      :ok -> Logger.debug "#{client_ip_string}: handshake successful"
    end
  end  
end