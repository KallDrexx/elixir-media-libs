defmodule RtmpServer.Handler do
  defmodule State do
    defstruct ip: nil,
              previous_headers: %{}
  end
  
  require Logger
  @moduledoc "Handles the rtmp socket connection"
  
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
      :ok -> 
        Logger.debug "#{client_ip_string}: handshake successful"
        
        state = %State{ip: ip}
        
        {:error, reason} = read_next_chunk(socket, transport, state)
        Logger.debug "#{client_ip_string}: connection error: #{reason}"
      
      {:error, reason} -> Logger.info "#{client_ip_string}: handshake failed (#{reason})"
    end
  end
  
  def read_next_chunk(socket, transport, state = %State{}) do
    client_ip = state.ip |> Tuple.to_list() |> Enum.join(".")
    
    with {:ok, {updated_headers, header, data}} <- RtmpCommon.Chunking.read_next_chunk(socket, transport, state.previous_headers),
              :ok <- log_chunk_details(client_ip, header, data),
              do: __MODULE__.read_next_chunk(socket, transport, %{state | previous_headers: updated_headers})
  end
  
  defp log_chunk_details(client_ip, header, data) do
    Logger.debug "#{client_ip}: Chunk type #{header.type} received for stream id #{header.stream_id}, " <>
                    "message id #{header.message_type_id}, size #{header.message_length}: #{inspect(data)}"
  end
end