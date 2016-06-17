defmodule RtmpSession.Messages.AudioData do
  @moduledoc """
  Data structure containing audio data
  """  
  
  @behaviour RtmpSession.RtmpMessage
  
  defstruct data: <<>>
  
  def parse(data) do
    %__MODULE__{data: data}
  end
  
  def serialize(%__MODULE__{data: data}) do    
    {:ok, %RtmpSession.RtmpMessage{
      message_type_id: 8,
      payload: data
    }} 
  end
  
  def get_default_chunk_stream_id(%__MODULE__{}),  do: 5
end