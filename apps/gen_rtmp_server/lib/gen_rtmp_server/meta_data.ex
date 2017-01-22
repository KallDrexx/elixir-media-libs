defmodule GenRtmpServer.MetaData do
  @type t :: %__MODULE__{
    details: Rtmp.StreamMetadata.t
  }

  defstruct details: nil
  
end