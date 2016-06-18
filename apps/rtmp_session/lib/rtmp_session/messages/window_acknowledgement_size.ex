defmodule RtmpSession.Messages.WindowAcknowledgementSize do
  @moduledoc """
  
  Sent to inform the peer of a change in how much
  data the receiver should receive before the sender
  expects and acknowledgement message sent back
  
  """
  
  @behaviour RtmpSession.RtmpMessage
  @type t :: %__MODULE__{}
  
  defstruct size: 0
  
  def deserialize(data) do
    <<size::32>> = data
    
    %__MODULE__{size: size}
  end
  
  def serialize(message = %__MODULE__{}) do
    {:ok, %RtmpSession.RtmpMessage{
      message_type_id: 5,
      payload: <<message.size::32>>
    }}
  end
  
  def get_default_chunk_stream_id(%__MODULE__{}),  do: 2
end