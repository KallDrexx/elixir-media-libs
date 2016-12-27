defmodule Rtmp.Protocol.Messages.SetChunkSize do
  @moduledoc """
  Represents a message that the sender is changing their
  maximum chunk size
  """
  
  @behaviour Rtmp.Protocol.RawMessage
  @type t :: %__MODULE__{
    size: non_neg_integer()
  }
  
  defstruct size: 128
  
  def deserialize(data) do
    <<0::1, size_value::31>> = data
    
    %__MODULE__{size: size_value}
  end
  
  def serialize(message = %__MODULE__{}) do
    {:ok, <<0::1, message.size::31>>}
  end
  
  def get_default_chunk_stream_id(%__MODULE__{}),  do: 2  
end