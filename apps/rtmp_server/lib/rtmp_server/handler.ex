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
        read_next_chunk(socket, transport, state)
      
      {:error, reason} -> Logger.info "#{client_ip_string}: handshake failed (#{reason})"
    end
  end
  
  def read_next_chunk(socket, transport, state = %State{}) do
    client_ip = state.ip |> Tuple.to_list() |> Enum.join(".")
    
    result = 
      with {:ok, current_header} <- RtmpCommon.Chunking.HeaderReader.read(socket, transport),
            previous_header = Map.get(state.previous_headers, current_header.stream_id),
            {:ok, data} <- RtmpCommon.Chunking.DataReader.read(previous_header, current_header, socket, transport),
            filled_in_header = fill_previous_header(previous_header, current_header),
            updated_header_map = Map.put(state.previous_headers, current_header.stream_id, filled_in_header),
            do: {:ok, { %{state | previous_headers: updated_header_map}, current_header, data}}
            
    case result do
      {:ok, {new_state, header, _data}} ->
        Logger.debug "#{client_ip}: Chunk type #{header.type} received for stream id #{header.stream_id}"
        __MODULE__.read_next_chunk(socket, transport, new_state)
        
      {:error, reason} -> Logger.debug "#{client_ip}: read failure: #{reason}"
    end
  end
  
  # Since some headers are missing information, we want to fill the previous header 
  # with as much information as possible, so we can have that data
  # for the next chunk that may come down without that info
  defp fill_previous_header(nil, current_header) do
    current_header
  end
  
  defp fill_previous_header(_, current_header = %RtmpCommon.Chunking.ChunkHeader{type: 0}) do
    current_header
  end
    
  defp fill_previous_header(previous_header, current_header = %RtmpCommon.Chunking.ChunkHeader{type: 1}) do
    %{current_header | message_stream_id: previous_header.message_stream_id}
  end
    
  defp fill_previous_header(previous_header, current_header = %RtmpCommon.Chunking.ChunkHeader{type: 2}) do
    %{current_header | 
      message_stream_id: previous_header.message_stream_id,
      message_type_id: previous_header.message_type_id,
      message_length: previous_header.message_length    
    }
  end
    
  defp fill_previous_header(previous_header, current_header = %RtmpCommon.Chunking.ChunkHeader{type: 3}) do
    %{current_header | 
      message_stream_id: previous_header.message_stream_id,
      message_type_id: previous_header.message_type_id,
      message_length: previous_header.message_length,
      timestamp: previous_header.timestamp    
    }
  end  
end