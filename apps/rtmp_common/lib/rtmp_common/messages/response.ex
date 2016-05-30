defmodule RtmpCommon.Messages.Response do
  defstruct stream_id: 0,
            message: nil,
            force_uncompressed: false
end