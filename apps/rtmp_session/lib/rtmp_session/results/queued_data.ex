defmodule RtmpSession.Results.QueuedData do
  @moduledoc """
  Represents information that has been queued up while processing
  RTMP data, and is awaiting to be handled
  """

  defstruct bytes_to_send: <<>>,
            queued_events: []
end