defmodule RtmpCommon.Messages.Types.SetChunkSize do
  @moduledoc """
  
  Represents a message that the sender is changing their
  maximum chunk size 
  
  """
  
  @behaviour RtmpCommon.Messages.Message
  
  defstruct size: 128
  
  def parse(data) do
    <<0::1, size_value::31>> = data
    
    %__MODULE__{size: size_value}
  end
  
  def serialize(message = %__MODULE__{}) do
    {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 1,
      data: <<0::1, message.size::31>>
    }}
  end
  
end