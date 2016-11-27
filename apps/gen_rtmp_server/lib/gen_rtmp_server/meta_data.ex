defmodule GenRtmpServer.MetaData do
  @type t :: %__MODULE__{
    details: RtmpSession.StreamMetadata.t
  }

  defstruct details: nil
  
end