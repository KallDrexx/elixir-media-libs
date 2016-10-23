defmodule RtmpServer.Handler do
  @moduledoc "Handles the rtmp socket connection"
  require Logger
  use GenServer
  
  defmodule State do
    defstruct socket: nil,
              transport: nil,
              session_id: nil,
              bytes_read: 0,
              bytes_sent: 0,
              handshake_completed: false,
              handshake_instance: nil,
              rtmp_session_instance: nil,
              director_instance: nil             
  end  
  
  @doc "Starts the handler for an accepted socket"
  def start_link(ref, socket, transport, opts) do
    :proc_lib.start_link(__MODULE__, :init, [ref, socket, transport, opts])
  end
  
  def init(ref, socket, transport, opts) do   
    :ok = :proc_lib.init_ack({:ok, self()})
    :ok = :ranch.accept_ack(ref)

    send(self(), {:perform_handshake, opts})
    :gen_server.enter_loop(__MODULE__, [], %State{socket: socket, transport: transport})   
  end
  
  def handle_info({:perform_handshake, initial_options}, state) do
    session_id = UUID.uuid4()
    
    {:ok, {ip, _port}} = :inet.peername(state.socket)
    client_ip_string = ip |> Tuple.to_list() |> Enum.join(".")
        
    _ = Logger.info "#{session_id}: client connected from ip #{client_ip_string}"

    {handshake_instance, %RtmpHandshake.ParseResult{bytes_to_send: bytes_to_send}} 
      = RtmpHandshake.new()

    :ok = state.transport.send(state.socket, bytes_to_send)

    session_config = create_session_config(initial_options)

    new_state = %{state |
      handshake_instance: handshake_instance,
      session_id: session_id,
      rtmp_session_instance: RtmpSession.new(0, session_id, session_config),

      #TODO: Pass in director module via opts
      director_instance: RtmpServer.Director.new(RtmpServer.AcceptAllDirector, session_id, state.socket)
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

        state = %{state |
          handshake_instance: nil,
          handshake_completed: true  
        }

        state = process_binary(state, remaining_binary)

        set_socket_options(state)
        {:noreply, state}
    end    
  end
  
  def handle_info({:tcp, _, binary}, state = %State{}) do
    state = process_binary(state, binary)
    {:noreply, state}
  end
  
  def handle_info({:tcp_closed, _}, state = %State{}) do
    _ = Logger.info "#{state.session_id}: socket closed" 
    {:stop, :normal, state}
  end
  
  def handle_info(message, state = %State{}) do
    _ = Logger.error "#{state.session_id}: Unknown message: #{inspect(message)}"
    
    set_socket_options(state)
    {:noreply, state}
  end
  
  defp set_socket_options(state = %State{}) do
    :ok = state.transport.setopts(state.socket, active: :once, packet: :raw)
  end

  defp process_binary(state, binary) do
    {session, results} = RtmpSession.process_bytes(state.rtmp_session_instance, binary)

    state.transport.send(state.socket, results.bytes_to_send)

    {director, session} = RtmpServer.Director.handle(state.director_instance, session, state.transport, results.events)    
    set_socket_options(state)

    %{state | 
      rtmp_session_instance: session,
      director_instance: director
    }
  end

  defp create_session_config(options) do
    config = %RtmpSession.SessionConfig{}
    config = case Keyword.fetch(options, :fms_version) do
      {:ok, value} -> %{config| fms_version: value}
      :error -> config
    end

    config = case Keyword.fetch(options, :chunk_size) do
      {:ok, value} -> %{config| chunk_size: value}
      :error -> config
    end

    config
  end
end