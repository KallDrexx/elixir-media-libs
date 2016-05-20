defmodule RtmpServer.Handler do
  @moduledoc "Handles the rtmp socket connection"
  require Logger
  use GenServer
  
  defmodule State do
    defstruct socket: nil,
              transport: nil,
              session_id: nil,
              chunk_deserializer: nil              
  end  
  
  @doc "Starts the handler for an accepted socket"
  def start_link(ref, socket, transport, opts) do
    :proc_lib.start_link(__MODULE__, :init, [ref, socket, transport, opts])
  end
  
  def init(ref, socket, transport, _opts) do   
    :ok = :proc_lib.init_ack({:ok, self()})
    :ok = :ranch.accept_ack(ref)
    
    send(self(), :perform_handshake)    
    :gen_server.enter_loop(__MODULE__, [], %State{socket: socket, transport: transport})    
  end
  
  def handle_info(:perform_handshake, state) do
    session_id = UUID.uuid4()
    
    {:ok, {ip, _port}} = :inet.peername(state.socket)
    client_ip_string = ip |> Tuple.to_list() |> Enum.join(".")
        
    Logger.info "#{session_id}: client connected from ip #{client_ip_string}"
    
    case RtmpServer.Handshake.process(state.socket, state.transport) do
      {:ok, _client_epoch} -> 
        set_socket_options(state)
        Logger.debug "#{session_id}: handshake successful"
        
        new_state = %{state | 
          session_id: session_id,
          chunk_deserializer: RtmpCommon.Chunking.Deserializer.new
        }
        
        {:noreply, new_state}
      
      {:error, reason} -> 
        Logger.info "#{session_id}: handshake failed (#{reason})"
        
        {:stop, {:handshake_failed, reason}, state}
    end
  end
  
  def handle_info({:tcp, _, binary}, state = %State{}) do
    {deserializer, chunks} = 
      RtmpCommon.Chunking.Deserializer.process(state.chunk_deserializer, binary)
      |> RtmpCommon.Chunking.Deserializer.get_deserialized_chunks()
      
    state_after_processing = process_chunk(state, chunks)
    new_state = %{state_after_processing | chunk_deserializer: deserializer}
    
    set_socket_options(state)
    {:noreply, new_state}
  end
  
  def handle_info({:tcp_closed, _}, state = %State{}) do
    Logger.info "#{state.session_id}: socket closed" 
    {:stop, :normal, state}
  end
  
  def handle_info(message, state = %State{}) do
    Logger.error "#{state.session_id}: Unknown message: #{inspect(message)}"
    
    set_socket_options(state)
    {:noreply, state}
  end
  
  defp set_socket_options(state = %State{}) do
    :ok = state.transport.setopts(state.socket, active: :once, packet: :raw)
  end
  
  defp process_chunk(state = %State{}, []) do
    state
  end
  
  defp process_chunk(state = %State{}, [{header = %RtmpCommon.Chunking.ChunkHeader{}, data} | rest]) do
    updated_state = case RtmpCommon.Messages.Deserializer.deserialize(header.message_type_id, data) do
      {:error, :unknown_message_type} ->
        Logger.error "#{state.session_id}: Unknown message received with type id: #{header.message_type_id}"
        state
        
      {:ok, message} -> 
        Logger.debug "#{state.session_id}: Message received: #{inspect(message)}"
        state
    end
    
    process_chunk(updated_state, rest)
  end

end