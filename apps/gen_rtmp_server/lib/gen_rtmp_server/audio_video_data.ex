defmodule GenRtmpServer.AudioVideoData do
  @type t :: %__MODULE__{
    data_type: :audio | :video,
    received_at_timestamp: pos_integer(),
    data: <<>>
  }

  defstruct  data_type: nil,
             received_at_timestamp: nil,
             data: <<>>
  
end