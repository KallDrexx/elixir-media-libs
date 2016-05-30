defmodule RtmpCommon.Messages.Types.Amf0Data do
  @moduledoc """
  Data structure containing metadata or user data, encoded in Amf0
  """  
  
  @behaviour RtmpCommon.Messages.Message
  
  defstruct parameters: []
  
  def parse(data) do
    objects = RtmpCommon.Amf0.deserialize(data)
    
    %__MODULE__{parameters: objects}
  end
  
  def serialize(%__MODULE__{parameters: params}) do
    binary = RtmpCommon.Amf0.serialize(params)
    
    {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 18,
      data: binary
    }} 
  end
  
  def get_default_chunk_stream_id(%__MODULE__{}),  do: 3
end