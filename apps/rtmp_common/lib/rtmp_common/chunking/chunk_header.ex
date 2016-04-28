defmodule RtmpCommon.Chunking.ChunkHeader do
  defstruct type: nil,
            stream_id: nil,
            timestamp: nil,
            message_length: nil,
            message_type_id: nil,
            message_stream_id: nil
end