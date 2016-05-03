defmodule RtmpCommon.Messages.Types.WindowAcknowledgementSize do
  @moduledoc """
  
  Sent to inform the peer of a change in how much
  data the receiver should receive before the sender
  expects and acknowledgement message sent back
  
  """
  
  @behaviour RtmpCommon.Messages.Message
  
  defstruct size: 0
  
  def parse(data) do
    <<size::32>> = data
    
    %__MODULE__{size: size}
  end
  
  def to_response(message = %__MODULE__{}) do
    {:ok, %RtmpCommon.Messages.Response{
      message_type_id: 5,
      data: <<message.size::32>>
    }}
  end
end