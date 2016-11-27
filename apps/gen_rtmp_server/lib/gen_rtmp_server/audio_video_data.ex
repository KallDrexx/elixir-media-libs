defmodule GenRtmpServer.AudioVideoData do
  @type t :: %__MODULE__{
    data_type: :audio | :video,
    data: <<>>
  }

  defstruct  data_type: nil,
             data: <<>>
  
end