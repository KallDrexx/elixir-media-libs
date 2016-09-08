defmodule RtmpSession.SessionResults do
  @moduledoc """
  Represents bytes to be sent to the peer, along with events that should
  be raised to the owner of the Rtmp Session
  """

  @type t :: %__MODULE__{
    bytes_to_send: iolist(),
    events: [RtmpSession.Events.t]
  }

  defstruct bytes_to_send: <<>>,
            events: []
end