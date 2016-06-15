defmodule RtmpSessionTest do
  use ExUnit.Case
  require Logger
  doctest RtmpSession

  test "Can parse Obs-1 recorded session" do
    reader = RecordedChunkReader.new("test/captured_sessions/obs-1/")
    session = RtmpSession.new(0)

    {session, reader} = read_data(session, reader)

    # TODO: check for expected queued events
  end

  defp read_data(session, reader) do
    case RecordedChunkReader.read_next(reader) do
      {reader, :done} -> 
        {session, reader}

      {reader, binary} ->
        session = RtmpSession.process_bytes(session, binary)
        read_data(session, reader) 
    end
  end
end