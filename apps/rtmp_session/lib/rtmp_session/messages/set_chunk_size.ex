defmodule RtmpSession.Messages.SetChunkSize do
  @moduledoc """  
  Represents a message that the sender is changing their
  maximum chunk size 
  
  """
  
  @behaviour RtmpSession.RtmpMessage
  @type t :: %__MODULE__{}
  
  defstruct size: 128
  
  def parse(data) do
    <<0::1, size_value::31>> = data
    
    %__MODULE__{size: size_value}
  end
  
  def serialize(message = %__MODULE__{}) do
    {:ok, %RtmpSession.RtmpMessage{
      message_type_id: 1,
      payload: <<0::1, message.size::31>>
    }}
  end
  
  def get_default_chunk_stream_id(%__MODULE__{}),  do: 2  
end