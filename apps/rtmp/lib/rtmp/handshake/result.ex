defmodule Rtmp.Handshake.Result do
  defstruct current_state: nil,
            bytes_to_send: <<>>
end