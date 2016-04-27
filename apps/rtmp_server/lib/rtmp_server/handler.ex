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
    
    Logger.debug "connection started"
    perform_handshake(socket, transport)
  end

  defp perform_handshake(socket, transport) do
    case RtmpServer.Handshake.process(socket, transport) do
      :ok -> Logger.debug "handshake completed"
      {:error, reason} -> Logger.debug "handshake failed due to #{reason}" 
    end
  end
  
end