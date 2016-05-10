defmodule RtmpCommon.ConnectionDetails do
  defstruct peer_chunk_size: 128,
            peer_window_size: nil,
            peer_bandwidth: nil,
            active_streams: %{}
end