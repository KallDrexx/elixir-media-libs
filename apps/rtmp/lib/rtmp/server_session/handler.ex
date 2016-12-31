defmodule Rtmp.ServerSession.Handler do
  @moduledoc """
  This module controls the process that controls the business logic
  of a server in an RTMP connection.

  The session handler can react to incoming RTMP input messages from
  the client by responding directly with RTMP output messages or by
  sending out event notifications for other processes to react to.

  The session handler then has an API for other processes to proactively
  trigger business logic (such as accepting a connection request) and cause
  RTMP messages to be sent out to the connected client.
  """

  require Logger
  use GenServer

  alias Rtmp.Protocol.DetailedMessage, as: DetailedMessage
  alias Rtmp.Protocol.Messages, as: Messages
  alias Rtmp.ServerSession.Events, as: Events
  alias Rtmp.ServerSession.Configuration, as: Configuration

  @type rtmp_output_handler :: pid
  @type session_handler :: pid
  @type event_notification_process :: pid
  @type rtmp_output_notification_function :: (rtmp_output_handler, %DetailedMessage{} -> :ok)
  @type event_receiver_process :: pid
  @type event_notification_function ::  (event_receiver_process, Events.t -> :ok)
  @type request_id :: non_neg_integer

  defmodule State do
    defstruct connection_id: nil,
              configuration: nil,
              start_time: nil,
              protocol_handler_pid: nil,
              protocol_output_notification_function: nil,
              event_receiver_pid: nil,
              event_notification_function: nil,
              current_stage: :started,
              specified_amf_version: 0,
              last_request_id: 0,
              active_requests: %{},
              connected_app_name: nil
  end

  @spec start_link(Rtmp.connection_id, Configuration.t) :: {:ok, session_handler}
  @doc "Starts a new session handler process"
  def start_link(connection_id, configuration = %Configuration{}) do
    GenServer.start_link(__MODULE__, [connection_id, configuration])
  end

  @spec set_event_handler(session_handler, event_notification_process, event_notification_function)
    :: :ok | :event_handler_already_set
  @doc "Specifies the process id and function to use to raise event notifications"
  def set_event_handler(session_pid, event_pid, event_function) do
    GenServer.call(session_pid, {:set_event_handler, {event_pid, event_function}})
  end

  @spec set_rtmp_output_handler(session_handler, rtmp_output_handler, rtmp_output_notification_function)
    :: :ok | :output_handler_already_set
  @doc "Specifies the process id and function to send outbound RTMP messages"
  def set_rtmp_output_handler(session_pid, output_pid, output_function) do
    GenServer.call(session_pid, {:set_output_handler, {output_pid, output_function}})
  end

  @spec handle_rtmp_input(session_handler, %DetailedMessage{}) :: :ok
  @doc "Passes an incoming RTMP message to the session handler"
  def handle_rtmp_input(pid, message = %DetailedMessage{}) do
    GenServer.cast(pid, {:rtmp_input, message})
  end

  @spec accept_request(session_handler, request_id) :: :ok
  @doc "Attempts to accept a request with the specified id"
  def accept_request(pid, request_id) do
    GenServer.cast(pid, {:accept_request, request_id})
  end

  def init([connection_id, configuration]) do
    state = %State{
      connection_id: connection_id,
      configuration: configuration,
      start_time: :os.system_time(:milli_seconds)
    }

    {:ok, state}
  end

  def handle_call({:set_event_handler, {event_pid, event_function}}, _from, state) do
    handler_set = state.event_receiver_pid != nil
    function_set = state.event_notification_function != nil
    case handler_set && function_set do
      true ->
        {:reply, :event_handler_already_set, state}

      false ->
        state = %{state | event_receiver_pid: event_pid, event_notification_function: event_function}
        {:reply, :ok, state}
    end
  end

  def handle_call({:set_output_handler, {output_pid, output_function}}, _from, state) do
    handler_set = state.protocol_handler_pid != nil
    function_set = state.protocol_output_notification_function != nil
    case handler_set && function_set do
      true ->
        {:reply, :event_handler_already_set, state}

      false ->
        state = %{state |
          protocol_handler_pid: output_pid,
          protocol_output_notification_function: output_function
        }

        {:reply, :ok, state}
    end
  end

  def handle_cast({:rtmp_input, message}, state) do
    cond do
      state.event_receiver_pid == nil -> raise("No event handler set")
      state.event_notification_function == nil -> raise("No event handler set")
      state.protocol_handler_pid == nil -> raise("No protocol handler set")
      state.protocol_output_notification_function == nil -> raise("No protocol handler set")
      true ->
        state = do_handle(state, message)
        {:noreply, state}
    end
  end

  def handle_cast({:accept_request, request_id}, state) do
    {request, remaining_requests} = Map.pop(state.active_requests, request_id)
    state = %{state | active_requests: remaining_requests}

    state = case request do
      {:connect, app_name} -> accept_connect_request(state, app_name)
    end

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

  defp handle_command(state = %State{current_stage: :started},
                      _stream_id,
                      "connect",
                      _transaction_id,
                      command_obj,
                      _args) do

    state = case command_obj["objectEncoding"] do
      x when x == 3 -> state = %{state | specified_amf_version: 3}
      _ -> state
    end

    app_name = String.replace_trailing(command_obj["app"], "/", "")
    request = {:connect, app_name}
    {state, request_id} = create_request(state, request)

    _ = Logger.debug("#{state.connection_id}: Connect command received on app #{app_name}")

    messages = [
      %Messages.SetPeerBandwidth{window_size: state.configuration.peer_bandwidth, limit_type: :dynamic},
      %Messages.WindowAcknowledgementSize{size: state.configuration.window_ack_size},
      %Messages.UserControl{type: :stream_begin, stream_id: 0},
      %Messages.Amf0Command{
        command_name: "onBWDone",
        transaction_id: 0,
        command_object: nil,
        additional_values: [8192]
      } # based on packet capture, not sure if 100% needed
    ]

    :ok = send_output_message(state, messages, 0, true)

    raise_event(state, %Events.ConnectionRequested{
      request_id: request_id,
      app_name: app_name
    })

    state
  end

  defp handle_command(state, stream_id, command_name, transaction_id, _command_obj, _args) do
    _ = Logger.warn("#{state.connection_id}: Unable to handle command '#{command_name}' while in stage '#{state.current_stage}' " <>
      "(stream id '#{stream_id}', transaction_id: #{transaction_id})")
    state
  end

  defp create_request(state, request) do
    request_id = state.last_request_id + 1
    state = %{state |
      last_request_id: request_id,
      active_requests: Map.put(state.active_requests, request_id, request)
    }

    {state, request_id}
  end

  defp accept_connect_request(state, app_name) do
    state = %{state |
      current_stage: :connected,
      connected_app_name: app_name
    }

    _ = Logger.debug("#{state.connection_id}: Accepted connection request for application '#{app_name}'")

    message = %Messages.Amf0Command{
      command_name: "_result",
      transaction_id: 1,
      command_object: %{
        "fmsVer" => state.configuration.fms_version,
        "capabilities" => 31
      },
      additional_values: [%{
        "level" => "status",
        "code" => "NetConnection.Connect.Success",
        "description" => "Connection succeeded",
        "objectEncoding" => state.specified_amf_version
      }]
    }

    :ok = send_output_message(state, message, 0)
    state
  end

  defp send_output_message(state, messages, stream_id, force_uncompressed \\ false)

  defp send_output_message(_, [], _, _) do
    :ok
  end

  defp send_output_message(state, [message | rest], stream_id, force_uncompressed) do
    response = form_output_message(state, message, stream_id, force_uncompressed)
    :ok = state.protocol_output_notification_function.(state.protocol_handler_pid, response)
    send_output_message(state, rest, stream_id, force_uncompressed)
  end

  defp send_output_message(state, message, stream_id, force_uncompressed) do
    send_output_message(state, [message], stream_id, force_uncompressed)
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

  defp raise_event(_, []) do
    :ok
  end

  defp raise_event(state, [event | rest]) do
    :ok = state.event_notification_function.(state.event_receiver_pid, event)
    raise_event(state, rest)
  end

  defp raise_event(state, event) do
    raise_event(state, [event])
  end
end