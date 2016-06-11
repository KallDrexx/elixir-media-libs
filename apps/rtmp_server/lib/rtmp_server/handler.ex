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
              start_epoch: nil,
              handshake_completed: false,
              handshake_instance: nil             
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

    {handshake_instance, %RtmpHandshake.ParseResult{bytes_to_send: bytes_to_send}} 
      = RtmpHandshake.new()

    :ok = state.transport.send(state.socket, bytes_to_send)

    new_state = %{state |
      handshake_instance: handshake_instance,
      session_id: session_id,
      chunk_deserializer: RtmpCommon.Chunking.Deserializer.new(),
      chunk_serializer: RtmpCommon.Chunking.Serializer.new(),
      message_handler: RtmpCommon.Messages.Handler.new(session_id),          
      start_epoch: :erlang.system_time(:milli_seconds)
    }

    set_socket_options(new_state)
    {:noreply, new_state}
  end

  def handle_info({:tcp, _, binary}, state = %State{handshake_completed: false}) do
    case RtmpHandshake.process_bytes(state.handshake_instance, binary) do
      {instance, result = %RtmpHandshake.ParseResult{current_state: :waiting_for_data}} ->
        if byte_size(result.bytes_to_send) > 0, do: state.transport.send(state.socket, result.bytes_to_send)

        new_state = %{state | handshake_instance: instance}
        set_socket_options(new_state)
        {:noreply, new_state}
      
      {instance, result = %RtmpHandshake.ParseResult{current_state: :success}} ->
        if byte_size(result.bytes_to_send) > 0, do: state.transport.send(state.socket, result.bytes_to_send)

        {_, %RtmpHandshake.HandshakeResult{remaining_binary: remaining_binary}}
          = RtmpHandshake.get_handshake_result(instance)

        new_state = %{state |
          handshake_instance: nil,
          handshake_completed: true  
        }

        set_socket_options(new_state)
        {:noreply, new_state}
    end    
  end
  
  def handle_info({:tcp, _, binary}, state = %State{}) do
    new_state = deserialize_chunks(binary, state)
    
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
  
  defp deserialize_chunks(binary, state) do
    {deserializer, chunks} = 
      RtmpCommon.Chunking.Deserializer.process(state.chunk_deserializer, binary)
      |> RtmpCommon.Chunking.Deserializer.get_deserialized_chunks()
      
    state = process_chunk(state, chunks)    
    peer_chunk_size = RtmpCommon.Messages.Handler.get_peer_chunk_size(state.message_handler)
    
    new_state = %{state | 
      bytes_read: state.bytes_read + byte_size(binary),
      chunk_deserializer: RtmpCommon.Chunking.Deserializer.set_max_chunk_size(deserializer, peer_chunk_size)
    }
    
    case RtmpCommon.Chunking.Deserializer.get_status(new_state.chunk_deserializer) do
      :processing -> deserialize_chunks(<<>>, new_state)
      :waiting_for_data -> new_state
    end
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
      RtmpCommon.Chunking.Serializer.serialize(state.chunk_serializer, 
                                                timestamp, 
                                                csid, 
                                                message, 
                                                stream_id, 
                                                response.force_uncompressed)
           
    state.transport.send(state.socket, binary)
    
    new_state = %{state |
      bytes_sent: state.bytes_sent + byte_size(binary),
      chunk_serializer: serializer
    }
    
    send_messages(rest, new_state)    
  end
end