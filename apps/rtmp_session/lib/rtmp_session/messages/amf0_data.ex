defmodule RtmpSession.Messages.Amf0Data do
  @moduledoc """
  Data structure containing metadata or user data, encoded in Amf0
  """  
  
  @behaviour RtmpSession.RtmpMessage
  
  defstruct parameters: []
  
  def parse(data) do
    {:ok, objects} = Amf0.deserialize(data)
    
    %__MODULE__{parameters: objects}
  end
  
  def serialize(%__MODULE__{parameters: params}) do
    binary = Amf0.serialize(params)
    
    {:ok, %RtmpSession.RtmpMessage{
      message_type_id: 18,
      payload: binary
    }} 
  end
  
  def get_default_chunk_stream_id(%__MODULE__{}),  do: 3
end