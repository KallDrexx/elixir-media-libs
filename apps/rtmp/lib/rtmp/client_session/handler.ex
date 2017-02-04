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
  #alias Rtmp.Protocol.Messages, as: Messages
  #alias Rtmp.ClientSession.Events, as: Events
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

    defstruct connection_id: nil
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
  
end