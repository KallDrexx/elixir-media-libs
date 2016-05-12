defmodule RtmpCommon.ConnectionDetails do
  defstruct peer_chunk_size: 128,
            peer_window_size: nil,
            peer_bandwidth: nil,
            peer_epoch: nil,
            active_streams: %{},
            app_name: nil
end