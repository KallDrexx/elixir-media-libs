defmodule Rtmp.Handshake.HandshakeResult do
  @type t :: %Rtmp.Handshake.HandshakeResult{
    peer_start_timestamp: nil | non_neg_integer(),
    remaining_binary: <<>>
  }

  defstruct peer_start_timestamp: nil,
            remaining_binary: <<>>
end