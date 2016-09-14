defmodule RtmpSession.DetailedMessage do
  @moduledoc """
  Represents the details of a deserialized RTMP message
  """

  @type t :: %__MODULE__{
    timestamp: non_neg_integer(),
    stream_id: non_neg_integer(),
    content: RtmpSession.deserialized_message
  }

  defstruct timestamp: nil,
            stream_id: nil,
            content: nil
end