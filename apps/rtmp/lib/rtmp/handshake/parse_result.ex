defmodule Rtmp.Handshake.ParseResult do
  @moduledoc """
  Represents the current results from a parse operation
  """
  
  @type t :: %Rtmp.Handshake.ParseResult{
    current_state: :waiting_for_data | :failure | :success,
    bytes_to_send: <<>>
  }

  defstruct current_state: :waiting_for_data,
            bytes_to_send: <<>>
end