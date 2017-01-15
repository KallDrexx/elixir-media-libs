defmodule Rtmp.Protocol.Handler do
  @moduledoc """
  This module controls the process that is responsible for serializing
  and deserializing RTMP chunk streams for a single peer in an RTMP
  connection.  Input bytes come in, get deserialized into RTMP messages,
  and then get sent off to the specified session handling process.  It can
  receive outbound RTMP messages that will then be serialized and sent off
  to the peer.

  Due to the way RTMP header compression works, it is expected that the
  protocol handler will receive every input byte of network communication
  after a successful handshake, and it will be the only system serializing
  and sending outbound RTMP messages to the peer.  If these assumptions are
  broken then there is a large chance the client or server will crash due
  to not being able to properly parse an RTMP chunk correctly.
  """

  require Logger
  use GenServer

  alias Rtmp.Protocol.ChunkIo, as: ChunkIo
  alias Rtmp.Protocol.RawMessage, as: RawMessage
  alias Rtmp.Protocol.DetailedMessage, as: DetailedMessage
  alias Rtmp.Protocol.Messages.SetChunkSize, as: SetChunkSize

  @type protocol_handler :: pid
  @type socket :: any
  @type socket_transport_module :: module
  @type session_process :: pid
  @type session_handler_module :: module

  defmodule State do
    @moduledoc false

    defstruct connection_id: nil,
              socket: nil,
              socket_module: nil,
              chunk_io_state: nil,
              session_process: nil,
              session_module: nil
  end

  @spec start_link(Rtmp.connection_id, socket, socket_transport_module) :: {:ok, protocol_handler}
  @doc "Starts a new protocol handler process"
  def start_link(connection_id, socket, socket_module) do
    GenServer.start_link(__MODULE__, [connection_id, socket, socket_module])
  end

  @spec set_session(protocol_handler, session_process, session_handler_module) :: :ok | :session_already_set
  @doc """
  Specifies the session handler process and function to use to send deserialized
  RTMP messages to for the session handler
  """
  def set_session(pid, session_process, session_module) do
    GenServer.call(pid, {:set_session, {session_process, session_module}})
  end

  @spec notify_input(protocol_handler, binary) :: :ok
  @doc """
  Notifies the protocol handler of incoming binary coming in from the socket
  """
  def notify_input(pid, binary) when is_binary(binary) do
    GenServer.cast(pid, {:socket_input, binary})
  end

  @spec send_message(protocol_handler, DetailedMessage.t) :: :ok
  @doc """
  Notifies the protocol handler of an rtmp message that should be serialized
  and sent to the peer.
  """
  def send_message(pid, message = %DetailedMessage{}) do
    GenServer.cast(pid, {:send_message, message})
  end

  def init([connection_id, socket, socket_module]) do
    state = %State{
      connection_id: connection_id,
      socket: socket,
      socket_module: socket_module,
      chunk_io_state: ChunkIo.new()
    }
    {:ok, state}
  end

  def handle_call({:set_session, {pid, session_module}}, _from, state) do
    state = %{state |
      session_process: pid,
      session_module: session_module
    }

    {:reply, :ok, state}
  end

  def handle_cast({:socket_input, binary}, state) do
    if state.session_process == nil || state.session_module == nil do
      raise ("Input received, but session process and notification functions are not set yet")
    end

    state = process_bytes(state, binary)
    {:noreply, state}
  end

  def handle_cast({:send_message, message}, state) do
    raw_message = RawMessage.pack(message)
    csid = get_csid_for_message_type(raw_message)

    {chunk_io_state, data} = ChunkIo.serialize(state.chunk_io_state, raw_message, csid)
    state = %{state | chunk_io_state: chunk_io_state}

    state = case message.content do
      %SetChunkSize{size: size} ->
        chunk_io_state = ChunkIo.set_sending_max_chunk_size(state.chunk_io_state, size)
        %{state | chunk_io_state: chunk_io_state}

      _ -> state
    end

    :ok = state.socket_module.send_data(state.socket, data)
    {:noreply, state}
  end

  defp process_bytes(state, binary) do
    {chunk_io_state, chunk_result} = ChunkIo.deserialize(state.chunk_io_state, binary)
    state = %{state | chunk_io_state: chunk_io_state}

    case chunk_result do
      :incomplete -> state
      :split_message -> process_bytes(state, <<>>)
      raw_message = %RawMessage{} -> act_on_message(state, raw_message)
    end
  end

  defp act_on_message(state, raw_message) do
    case RawMessage.unpack(raw_message) do
      {:error, :unknown_message_type} ->
        _ = Logger.error "#{state.connection_id}: Received message of type #{raw_message.message_type_id} but we have no known way to unpack it!"
        state

      {:ok, message = %DetailedMessage{content: %SetChunkSize{size: size}}} ->
        chunk_io_state = ChunkIo.set_receiving_max_chunk_size(state.chunk_io_state, size)
        state = %{state | chunk_io_state: chunk_io_state}

        :ok = state.session_module.handle_rtmp_input(state.session_process, message)
        process_bytes(state, <<>>)

      {:ok, message = %DetailedMessage{}} ->
        :ok = state.session_module.handle_rtmp_input(state.session_process, message)
        process_bytes(state, <<>>)
    end
  end

  # Csid seems to mostly be for better utilizing compression by spreading
  # different message types among different chunk stream ids.  It also allows
  # video and audio data to track different timestamps then other messages.
  # These numbers are just based on observations of current client-server activity
  defp get_csid_for_message_type(%RawMessage{message_type_id: 1}), do: 2
  defp get_csid_for_message_type(%RawMessage{message_type_id: 2}), do: 2
  defp get_csid_for_message_type(%RawMessage{message_type_id: 3}), do: 2
  defp get_csid_for_message_type(%RawMessage{message_type_id: 4}), do: 2
  defp get_csid_for_message_type(%RawMessage{message_type_id: 5}), do: 2
  defp get_csid_for_message_type(%RawMessage{message_type_id: 6}), do: 2
  defp get_csid_for_message_type(%RawMessage{message_type_id: 18}), do: 3
  defp get_csid_for_message_type(%RawMessage{message_type_id: 19}), do: 3
  defp get_csid_for_message_type(%RawMessage{message_type_id: 9}), do: 21
  defp get_csid_for_message_type(%RawMessage{message_type_id: 8}), do: 20
  defp get_csid_for_message_type(%RawMessage{message_type_id: _}), do: 6
end