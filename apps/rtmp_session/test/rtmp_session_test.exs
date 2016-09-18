defmodule RtmpSessionTest do
  use ExUnit.Case
  require Logger
  doctest RtmpSession

  alias RtmpSession.Events, as: Events

  test "Can parse Obs-1 recorded session" do
    reader = RecordedChunkReader.new("test/captured_sessions/obs-1/")
    session = RtmpSession.new(0)

    {_session, _reader} = read_data(session, reader)

    # TODO: check for expected events
    # assert(false)
  end

  defp read_data(session, reader) do
    case RecordedChunkReader.read_next(reader) do
      {reader, :done} -> 
        {session, reader}

      {reader, binary} ->
        {session, results} = RtmpSession.process_bytes(session, binary)
        session = handle_events(session, results.events)
                
        read_data(session, reader) 
    end
  end

  defp handle_events(session, []) do
    session
  end

  defp handle_events(session, [%Events.PeerChunkSizeChanged{} | tail]) do
    handle_events(session, tail)
  end

  defp handle_events(session, [%Events.ConnectionRequested{request_id: request_id} | tail]) do
    {session, results} = RtmpSession.accept_request(session, request_id)
    session = handle_events(session, results.events)

    handle_events(session, tail)
  end

  defp handle_events(session, [%Events.PeerChunkSizeChanged{} | tail]) do
    handle_events(session, tail)
  end

  defp handle_events(session, [%Events.PublishStreamRequested{request_id: request_id} | tail]) do
    {session, results} = RtmpSession.accept_request(session, request_id)
    session = handle_events(session, results.events)

    handle_events(session, tail)
  end

  defp handle_events(session, [event | tail]) do
    Logger.warn "No test code to handle event of type #{inspect event}"
    handle_events(session, tail)
  end
end
