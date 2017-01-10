defmodule Rtmp.Protocol.DetailedMessage do
  @moduledoc """
  Represents the details of a deserialized RTMP message
  """

  @type t :: %__MODULE__{
    timestamp: non_neg_integer,
    stream_id: non_neg_integer,
    content: Rtmp.deserialized_message,
    force_uncompressed: boolean,
    deserialization_system_time: pos_integer
  }

  defstruct timestamp: nil,
            stream_id: nil,
            content: nil,
            force_uncompressed: false,
            deserialization_system_time: nil
end