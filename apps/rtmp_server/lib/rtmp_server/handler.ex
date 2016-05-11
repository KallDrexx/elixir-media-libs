defmodule RtmpServer.Handler do
  defmodule State do
    defstruct ip: nil,
              previous_headers: %{},
              connection_details: %RtmpCommon.ConnectionDetails{}
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
      {:ok, client_epoch} -> 
        Logger.debug "#{client_ip_string}: handshake successful"
        
        state = %State{
          ip: ip, 
          connection_details: %RtmpCommon.ConnectionDetails{peer_epoch: client_epoch}
        }
        
        {:error, reason} = read_next_chunk(socket, transport, state)
        Logger.debug "#{client_ip_string}: connection error: #{reason}"
      
      {:error, reason} -> Logger.info "#{client_ip_string}: handshake failed (#{reason})"
    end
  end
  
  def read_next_chunk(socket, transport, state = %State{}) do    
    case RtmpCommon.Chunking.read_next_chunk(socket, transport, state.previous_headers) do
      {:ok, {updated_headers, header, data}} ->
        process_chunk(socket, transport, %{state | previous_headers: updated_headers}, header, data)
        
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp process_chunk(socket, transport, state, chunk_header, chunk_data) do
    client_ip = state.ip |> Tuple.to_list() |> Enum.join(".")
    
    result = with {:ok, received_message} <- RtmpCommon.Messages.Parser.parse(chunk_header.message_type_id, chunk_data),
                  :ok <- log_received_message(client_ip, received_message),
                  do: RtmpCommon.MessageHandler.handle(received_message, state.connection_details)
                  
    case result do
      {:ok, {new_connection_details, _response}} ->
        __MODULE__.read_next_chunk(socket, transport, %{state | connection_details: new_connection_details})
        
      {:error, {:no_handler_for_message, message_type}} ->
        Logger.debug "#{client_ip}: no handler for message: #{inspect(message_type)}"
        __MODULE__.read_next_chunk(socket, transport, state)
    end
  end
  
  defp log_received_message(client_ip, message) do
    Logger.debug "#{client_ip}: Message received: #{inspect(message)}"
  end
end