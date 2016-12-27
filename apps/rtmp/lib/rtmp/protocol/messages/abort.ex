defmodule Rtmp.Protocol.Messages.Abort do
  @moduledoc """
  
  Message used to notify the peer that if it is waiting
  for chunks to complete a message, then discard the partially
  received message
  
  """
  
  @behaviour Rtmp.Protocol.RawMessage
  @type t :: %__MODULE__{}
  
  defstruct stream_id: nil
  
  def deserialize(data) do
    <<stream_id::32>> = data
    
    %__MODULE__{stream_id: stream_id}
  end
  
  def serialize(message = %__MODULE__{}) do
    {:ok, <<message.stream_id::size(4)-unit(8)>>}
  end
  
  def get_default_chunk_stream_id(%__MODULE__{}),  do: 2
end