defmodule Rtmp.ClientSession.Handler do
  @moduledoc """
  This module controls the process that processes the busines logic
  of a client in an RTMP connection.

  When RTMP messages come in from the server, it either responds with 
  response messages or raises events to be handled by the event 
  receiver process.  This allows for consumers to be flexible in how
  they utilize the RTMP client.
  """

  require Logger
  use GenServer

  alias Rtmp.Protocol.DetailedMessage, as: DetailedMessage
  alias Rtmp.Protocol.Messages, as: Messages
  alias Rtmp.ClientSession.Events, as: Events
  alias Rtmp.ClientSession.Configuration, as: Configuration

  @type session_handler_process :: pid
  @type protocol_handler_process :: pid
  @type protocol_handler_module :: module
  @type event_receiver_process :: pid
  @type event_receiver_module :: module
  @type av_type :: :audio | :video
  @type publish_type :: :live

  @behaviour Rtmp.Behaviours.SessionHandler

  defmodule State do
    @moduledoc false

    defstruct connection_id: nil,
              configuration: nil,
              start_time: nil,
              protocol_handler_pid: nil,
              protocol_handler_module: nil,
              event_receiver_pid: nil,
              event_receiver_module: nil,
              current_status: :started,
              connected_app_name: nil,
              last_transaction_id: 0,
              open_transactions: %{}
  end

  defmodule Transaction do
    @moduledoc false

    defstruct id: nil,
              type: nil,
              data: nil
  end

  @spec start_link(Rtmp.connection_id, Configuration.t) :: {:ok, session_handler_process}
  @doc "Starts a new client session handler process"
  def start_link(connection_id, configuration = %Configuration{}) do
    GenServer.start_link(__MODULE__, [connection_id, configuration])
  end

  @spec set_event_handler(session_handler_process, event_receiver_process, event_receiver_module)
    :: :ok | :handler_already_set
  @doc """
  Specifies the process id and function to use to raise event notifications.

  It is expected that the module passed in implements the `Rtmp.Behaviours.EventReceiver` behaviour.
  """
  def set_event_handler(session_pid, event_pid, event_module) do
    GenServer.call(session_pid, {:set_event_handler, {event_pid, event_module}})
  end

  @spec set_protocol_handler(session_handler_process, protocol_handler_process, protocol_handler_module)
    :: :ok | :handler_already_set
  @doc """
  Specifies the process id and function to send outbound RTMP messages

  It is expected that the module passed in implements the `Rtmp.Behaviours.ProtocolHandler` behaviour.
  """
  def set_protocol_handler(session_pid, protocol_handler_pid, protocol_handler_module) do
    GenServer.call(session_pid, {:set_protocol_handler, {protocol_handler_pid, protocol_handler_module}})
  end

  @spec handle_rtmp_input(session_handler_process, DetailedMessage.t) :: :ok
  @doc "Passes an incoming RTMP message to the session handler"
  def handle_rtmp_input(pid, message = %DetailedMessage{}) do
    GenServer.cast(pid, {:rtmp_input, message})
  end

  @spec notify_byte_count(Rtmp.Behaviours.SessionHandler.session_handler_pid, Rtmp.Behaviours.SessionHandler.io_count_direction, non_neg_integer) :: :ok
  @doc "Notifies the session handler of new input or output byte totals"
  def notify_byte_count(pid, :bytes_received, total), do: GenServer.cast(pid, {:byte_count_update, :bytes_received, total})
  def notify_byte_count(pid, :bytes_sent, total),     do: GenServer.cast(pid, {:byte_count_update, :bytes_sent, total})

  @spec request_connection(session_handler_process, Rtmp.app_name) :: :ok
  @doc """
  Executes a request to send an RTMP connection request for the specified application name.  The
  response will come as a `Rtmp.ClientSession.Events.ConnectionResponseReceived` event.  
  """
  def request_connection(pid, app_name) do
    GenServer.cast(pid, {:connect, app_name})
  end

  @spec request_playback(session_handler_process, Rtmp.stream_key) :: :ok
  @doc """
  Sends a request to play from the specified stream key.  The response will come back as
  a `Rtmp.ClientSession.Events.PlayResponseReceived` event.
  """
  def request_playback(pid, stream_key) do
    GenServer.cast(pid, {:request_playback, stream_key})
  end

  @spec stop_playback(session_handler_process, Rtmp.stream_key) :: :ok
  @doc """
  Attempts to stop playback for the specified stream key.  Does nothing if we do not have an active
  playback session on the specified stream key
  """
  def stop_playback(pid, stream_key) do
    GenServer.cast(pid, {:stop_playback, stream_key})
  end

  @spec request_publish(session_handler_process, Rtmp.stream_key, publish_type) :: :ok
  @doc """
  Sends a request to the server that the client wishes to publish data on the specified stream key.
  The response will come as a `Rtmp.ClientSession.Events.PublishResponseReceived` response being raised
  """
  def request_publish(pid, stream_key, publish_type) do
    GenServer.cast(pid, {:request_publish, stream_key, publish_type})
  end  

  @spec publish_metadata(session_handler_process, Rtmp.stream_key, Rtmp.StreamMetadata.t) :: :ok
  @doc """
  Sends new metadata to the server over the specified stream key.  This is ignored if we are not
  in an active publishing session on that stream key
  """
  def publish_metadata(pid, stream_key, metadata) do
    GenServer.cast(pid, {:publish_metadata, stream_key, metadata})
  end

  @spec publish_av_data(session_handler_process, Rtmp.stream_key, av_type, binary) :: :ok
  @doc """
  Sends audio or video data to the server over the specified stream key.  This is ignored if we are not
  in an active publishing session for that stream key.
  """
  def publish_av_data(pid, stream_key, av_type, data) do
    GenServer.cast(pid, {:publish_av_data, stream_key, av_type, data})
  end

  @spec stop_publish(session_handler_process, Rtmp.stream_key) :: :ok
  @doc """
  Attempts to stop publishing on the specified stream key.  This is ignored if we are not actively
  publishing on that stream key.
  """
  def stop_publish(pid, stream_key) do
    GenServer.cast(pid, {:stop_publish, stream_key})
  end

  def init([connection_id, configuration]) do
    state = %State{
      connection_id: connection_id,
      configuration: configuration,
      start_time: :os.system_time(:milli_seconds)
    }

    {:ok, state}
  end

  def handle_call({:set_event_handler, {event_pid, event_receiver_module}}, _from, state) do
    handler_set = state.event_receiver_pid != nil
    function_set = state.event_receiver_module != nil
    case handler_set && function_set do
      true ->
        {:reply, :event_handler_already_set, state}

      false ->
        state = %{state | event_receiver_pid: event_pid, event_receiver_module: event_receiver_module}
        {:reply, :ok, state}
    end
  end

  def handle_call({:set_protocol_handler, {protocol_handler_pid, protocol_handler_module}}, _from, state) do
    handler_set = state.protocol_handler_pid != nil
    function_set = state.protocol_handler_module != nil
    case handler_set && function_set do
      true ->
        {:reply, :event_handler_already_set, state}

      false ->
        state = %{state |
          protocol_handler_pid: protocol_handler_pid,
          protocol_handler_module: protocol_handler_module
        }

        {:reply, :ok, state}
    end
  end

  def handle_cast({:rtmp_input, message}, state) do
    cond do
      state.event_receiver_pid == nil -> raise("No event handler set")
      state.event_receiver_module == nil -> raise("No event handler set")
      state.protocol_handler_pid == nil -> raise("No protocol handler set")
      state.protocol_handler_module == nil -> raise("No protocol handler set")
      true ->
        state = do_handle(state, message)
        {:noreply, state}
    end
  end

  def handle_cast({:connect, app_name}, state) do
    case state.current_status do
      :started ->
        state = send_connect_command(state, app_name)
        {:noreply, state}

      _ ->
        _ = Logger.warn("#{state.connection_id}: Attempted connection while in #{state.current_status} state, ignoring...")
        {:noreply, state}
    end
  end

  def handle_info(message, state) do
    _ = Logger.info("#{state.connection_id}: Session handler process received unknown erlang message: #{inspect(message)}")
    {:noreply, state}
  end

  defp do_handle(state, message = %DetailedMessage{content: %Messages.Amf0Command{}}) do
    handle_command(state,
                   message.stream_id,
                   message.content.command_name,
                   message.content.transaction_id,
                   message.content.command_object,
                   message.content.additional_values)
  end

  defp do_handle(state, message = %DetailedMessage{content: %{__struct__: message_type}}) do
    simple_name = String.replace(to_string(message_type), "Elixir.Rtmp.Protocol.Messages.", "")

    _ = Logger.warn("#{state.connection_id}: Unable to handle #{simple_name} message on stream id #{message.stream_id}")
    state
  end

  defp handle_command(state, _stream_id, "_result", transaction_id, command_object, additional_values) do
    case Map.get(state.open_transactions, transaction_id) do
      nil ->
        _ = Logger.warn("#{state.connection_id}: Received result for unknown transaction id #{transaction_id}")
        state

      transaction ->
        state = %{state | open_transactions: Map.delete(state.open_transactions, transaction_id)}
        case transaction.type do
          :connect -> handle_connect_result(state, transaction, command_object, additional_values)
        end
    end
  end

  defp handle_connect_result(state, transaction, _command_object, [arguments = %{}]) do
    case arguments["code"] do
      "NetConnection.Connect.Success" ->
        state = %{state | 
          current_status: :connected,
          connected_app_name: transaction.data
        }

        event = %Events.ConnectionResponseReceived {
          was_accepted: true,
          response_text: arguments["description"]
        }

        :ok = raise_event(state, event)
        state
    end
  end

  defp send_connect_command(state, app_name) do
    {transaction, state} = form_transaction(state, :connect, app_name)
    command =  %Messages.Amf0Command{
      command_name: "connect",
      transaction_id: transaction.id,
      command_object: %{
        "app" => app_name,
        "flashVer" => state.configuration.flash_version,
        "objectEncoding" => 0
      },
      additional_values: []
    }

    :ok = send_output_message(state, command, 0, false)

    %{state | 
      current_status: :connecting,
      open_transactions: Map.put(state.open_transactions, transaction.id, transaction)
    }
  end

  defp form_transaction(state, type, data) do
    transaction = %Transaction{
      id: state.last_transaction_id + 1,
      type: type,
      data: data
    }

    state = %{state | last_transaction_id: transaction.id}
    {transaction, state}
  end

  defp form_output_message(state, message_content, stream_id, force_uncompressed) do
    %DetailedMessage{
      timestamp: get_current_rtmp_epoch(state),
      stream_id: stream_id,
      content: message_content,
      force_uncompressed: force_uncompressed
    }
  end

  defp get_current_rtmp_epoch(state) do
    time_since_start = :os.system_time(:milli_seconds) - state.start_time
    Rtmp.Protocol.RtmpTime.to_rtmp_timestamp(time_since_start)
  end

  defp send_output_message(_, [], _, _) do
    :ok
  end

  defp send_output_message(state, [message | rest], stream_id, force_uncompressed) do
    response = form_output_message(state, message, stream_id, force_uncompressed)
    :ok = state.protocol_handler_module.send_message(state.protocol_handler_pid, response)
    send_output_message(state, rest, stream_id, force_uncompressed)
  end

  defp send_output_message(state, message, stream_id, force_uncompressed) do
    send_output_message(state, [message], stream_id, force_uncompressed)
  end

  defp raise_event(_, []) do
    :ok
  end

  defp raise_event(state, [event | rest]) do
    :ok = state.event_receiver_module.send_event(state.event_receiver_pid, event)
    raise_event(state, rest)
  end

  defp raise_event(state, event) do
    raise_event(state, [event])
  end
  
end