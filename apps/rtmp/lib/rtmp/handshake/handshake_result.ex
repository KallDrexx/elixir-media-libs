defmodule Rtmp.Handshake.HandshakeResult do
  @moduledoc "Resulting information after processing a handshake operation"

  @type t :: %Rtmp.Handshake.HandshakeResult{
    peer_start_timestamp: nil | non_neg_integer(),
    remaining_binary: binary
  }

  defstruct peer_start_timestamp: nil,
            remaining_binary: <<>>
end