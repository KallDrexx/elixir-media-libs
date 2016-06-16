defmodule RtmpSession.Messages.RtmpMessage do
  defstruct timestamp: nil,
            message_type_id: nil,
            payload: <<>>
end