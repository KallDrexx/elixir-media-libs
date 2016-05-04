defmodule RtmpCommon.Messages.Types.Abort do
  @moduledoc """
  
  Message used to notify the peer that if it is waiting
  for chunks to complete a message, then discard the partially
  received message
  
  """
  
  @behaviour RtmpCommon.Messages.Message
  
  defstruct stream_id: nil
  
  def parse(data) do
    <<stream_id::32>> = data
    
    %__MODULE__{stream_id: stream_id}
  end
  
  def serialize(message = %__MODULE__{}) do
    {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 2,
      data: <<message.stream_id::size(4)-unit(8)>>
    }}
  end
end