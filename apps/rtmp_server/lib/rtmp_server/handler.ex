defmodule RtmpServer.Handler do
  @moduledoc "Handles the rtmp socket connection"
  require Logger
  use GenServer
  
  defmodule State do
    defstruct socket: nil,
              transport: nil,
              session_id: nil,
              chunk_deserializer: nil,
              chunk_serializer: nil,
              message_handler: nil,
              bytes_read: 0,
              bytes_sent: 0,
              start_epoch: nil              
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
          chunk_deserializer: RtmpCommon.Chunking.Deserializer.new(),
          chunk_serializer: RtmpCommon.Chunking.Serializer.new(),
          message_handler: RtmpCommon.Messages.Handler.new(session_id),          
          start_epoch: :erlang.system_time(:milli_seconds)
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
    new_state = %{state_after_processing | 
      chunk_deserializer: deserializer, 
      bytes_read: state_after_processing.bytes_read + byte_size(binary)
    }
    
    set_socket_options(new_state)
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
        
        {handler, responses} =
          RtmpCommon.Messages.Handler.handle(state.message_handler, message)
          |> RtmpCommon.Messages.Handler.get_responses()
          
        send_messages(responses, %{state | message_handler: handler})
    end
    
    process_chunk(updated_state, rest)
  end

  defp send_messages([], state) do
    state
  end 
  
  defp send_messages([response = %RtmpCommon.Messages.Response{} | rest], state) do    
    timestamp = 
      :erlang.system_time(:milli_seconds) - state.start_epoch
      |> RtmpCommon.RtmpTime.to_rtmp_timestamp()
      
    csid = RtmpCommon.Chunking.DefaultCsidResolver.get_csid(response.message)
    message = response.message
    stream_id = response.stream_id
    
    Logger.debug "#{state.session_id}: Sending message: csid: #{csid}, timestamp: #{timestamp}, " <>
                  "sid: #{stream_id}, message: #{inspect(message)}"
    
    {serializer, binary} = 
      RtmpCommon.Chunking.Serializer.serialize(state.chunk_serializer, timestamp, csid, message, stream_id)
      
    state.transport.send(state.socket, binary)
    
    new_state = %{state |
      bytes_sent: state.bytes_sent + byte_size(binary),
      chunk_serializer: serializer
    }
    
    send_messages(rest, new_state)    
  end
end