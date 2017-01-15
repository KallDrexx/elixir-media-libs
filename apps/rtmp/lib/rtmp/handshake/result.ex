defmodule Rtmp.Handshake.Result do
  @moduledoc false
  
  defstruct current_state: nil,
            bytes_to_send: <<>>
end