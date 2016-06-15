defmodule RtmpSession.SessionResults do
  @moduledoc """
  Represents results that have been gathered since the last time 
  session results were gathered
  """

  defstruct bytes_to_send: <<>>,
            queued_events: []
end