defmodule RtmpServer.Director do
  @moduledoc """
  The RTMP server director is an abstraction of the processing logic of the RTMP session
  events and allowing other applications utilizing the RTMP server to fully customize
  its RTMP flow.
  """

  alias RtmpSession.Events, as: RtmpEvents

  require Logger

  @type director_command :: :ignore | :disconnect
  @type request_result :: :accepted | {:rejected, director_command, String.t}
  @type notification_result :: :ok | {:error, director_command, String.t}

  @callback handle_request(RtmpServer.session_id, RtmpEvents.ConnectionRequested.t) :: request_result 
  @callback handle_request(RtmpServer.session_id, RtmpEvents.PublishStreamRequested.t) :: request_result
  @callback handle_request(RtmpServer.session_id, RtmpEvents.ReleaseStreamRequested.t) :: request_result
  @callback handle_notification(RtmpServer.session_id, RtmpEvents.StreamMetaDataChanged.t) :: notification_result
  @callback handle_notification(RtmpServer.session_id, RtmpEvents.AudioVideoDataReceived.t) :: notification_result

  defmodule State do
    defstruct implementation_module: nil,
              session_id: nil,
              socket: nil
  end

  @spec new(module(), String.t, any()) :: %State{}
  def new(implementation, session_id, socket) when is_atom(implementation) do
    %State{
      implementation_module: implementation,
      session_id: session_id,
      socket: socket
    }
  end

  @spec handle(%State{}, RtmpSession.t, module(), [RtmpEvents.t]) :: {%State{}, RtmpSession.t}
  def handle(state = %State{}, session, transport, events) do
    do_handle(state, session, transport, events)
  end

  defp do_handle(state, session, _transport, []) do
    {state, session}
  end

  defp do_handle(state, session, transport, [event = %RtmpEvents.ConnectionRequested{} | tail]) do
    case state.implementation_module.handle_request(state.session_id, event) do
      {:rejected, command, reason} -> 
        _ = log(:info, state.session_id, "Connection request denied (app: '#{event.app_name}') - #{reason}")

        case command do
          :disconnect -> transport.close(state.socket)
          _ -> :ok
        end
        
        {state, session}

      :accepted ->
        _ = log(:info, state.session_id, "Connection request accepted (app: '#{event.app_name}')")
        {session, results} = RtmpSession.accept_request(session, event.request_id)
        
        transport.send(state.socket, results.bytes_to_send)
        {state, session} = do_handle(state, session, transport, results.events)

        do_handle(state, session, transport, tail)
    end
  end

  defp do_handle(state, session, transport, [event = %RtmpEvents.PublishStreamRequested{} | tail]) do
    case state.implementation_module.handle_request(state.session_id, event) do
      {:rejected, command, reason} -> 
        _ = log(:info, state.session_id, "Publish stream request denied (app: '#{event.app_name}', key: '#{event.stream_key}') - #{reason}")

        # TODO: notify session of the rejection
        case command do
          :disconnect -> transport.close(state.socket)
          _ -> :ok
        end

        do_handle(state, session, transport, tail)

      :accepted ->
        _ = log(:info, state.session_id, "Publish stream request accepted (app: '#{event.app_name}', key: '#{event.stream_key}')")
        {session, results} = RtmpSession.accept_request(session, event.request_id)
        
        transport.send(state.socket, results.bytes_to_send)
        {state, session} = do_handle(state, session, transport, results.events)

        do_handle(state, session, transport, tail)
    end
  end

  defp do_handle(state, session, transport, [event = %RtmpEvents.ReleaseStreamRequested{} | tail]) do
    case state.implementation_module.handle_request(state.session_id, event) do
      {:rejected, command, reason} -> 
        _ = log(:info, state.session_id, "Release stream request denied (app: '#{event.app_name}', key: '#{event.stream_key}') - #{reason}")

        # TODO: notify session of the rejection
        case command do
          :disconnect -> transport.close(state.socket)
          _ -> :ok
        end

        do_handle(state, session, transport, tail)

      :accepted ->
        _ = log(:info, state.session_id, "Release stream request accepted (app: '#{event.app_name}', key: '#{event.stream_key}')")
        {session, results} = RtmpSession.accept_request(session, event.request_id)
        
        transport.send(state.socket, results.bytes_to_send)
        {state, session} = do_handle(state, session, transport, results.events)

        do_handle(state, session, transport, tail)
    end
  end

  defp do_handle(state, session, transport, [event = %RtmpEvents.StreamMetaDataChanged{} | tail]) do
    case state.implementation_module.handle_notification(state.session_id, event) do
      {:error, command, reason} -> 
        _ = log(:info, state.session_id, "Stream metadata changed notification failed (app: '#{event.app_name}', key: '#{event.stream_key}') - #{reason}")

        case command do
          :disconnect -> transport.close(state.socket)
          _ -> :ok
        end

        do_handle(state, session, transport, tail)

      :ok ->
        _ = log(:info, state.session_id, "Stream metadata changed notification succeeded (app: '#{event.app_name}', key: '#{event.stream_key}')")
        do_handle(state, session, transport, tail)
    end
  end

  defp do_handle(state, session, transport, [event = %RtmpEvents.AudioVideoDataReceived{} | tail]) do
    case state.implementation_module.handle_notification(state.session_id, event) do
      {:error, command, reason} -> 
        _ = log(:info, state.session_id, "Audio/Video data received notification failed (app: '#{event.app_name}', key: '#{event.stream_key}') - #{reason}")        

        case command do
          :disconnect -> transport.close(state.socket)
          _ -> :ok
        end

        do_handle(state, session, transport, tail)

      :ok ->
        # Don't log as this will get spammy
        do_handle(state, session, transport, tail)
    end
  end

  defp do_handle(state, session, transport, [event | tail]) do
    _ = log(:warn, state.session_id, "No code to handle RTMP session event of type #{inspect(event)}")
    do_handle(state, session, transport, tail)
  end

  defp log(level, session_id, message) do
    full_message = "#{session_id}: #{message}"

    case level do
      :info -> Logger.info full_message
      :warn -> Logger.warn full_message
    end
  end
end