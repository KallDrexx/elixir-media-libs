defmodule RtmpHandshake.HandshakeResult do
  @type t :: %RtmpHandshake.HandshakeResult{
    peer_start_timestamp: nil | non_neg_integer(),
    remaining_binary: <<>>
  }

  defstruct peer_start_timestamp: nil,
            remaining_binary: <<>>
end