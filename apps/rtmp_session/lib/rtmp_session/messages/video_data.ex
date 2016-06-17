defmodule RtmpSession.Messages.VideoData do
  @moduledoc """
  Data structure containing video data
  """  
  
  @behaviour RtmpSession.RtmpMessage
  
  defstruct data: <<>>
  
  def parse(data) do
    %__MODULE__{data: data}
  end
  
  def serialize(%__MODULE__{data: data}) do    
    {:ok, %RtmpSession.RtmpMessage{
      message_type_id: 9,
      payload: data
    }} 
  end
  
  def get_default_chunk_stream_id(%__MODULE__{}),  do: 4
end