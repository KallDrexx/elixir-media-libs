defmodule Rtmp.Protocol.Messages.VideoData do
  @moduledoc """
  Data structure containing video data
  """  
  
  @behaviour Rtmp.Protocol.RawMessage
  @type t :: %__MODULE__{}
  
  defstruct data: <<>>
  
  def deserialize(data) do
    %__MODULE__{data: data}
  end
  
  def serialize(%__MODULE__{data: data}) do    
    {:ok, data}
  end
  
  def get_default_chunk_stream_id(%__MODULE__{}),  do: 4
end