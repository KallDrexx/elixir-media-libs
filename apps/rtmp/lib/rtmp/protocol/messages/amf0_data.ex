defmodule Rtmp.Protocol.Messages.Amf0Data do
  @moduledoc """
  Data structure containing metadata or user data, encoded in Amf0
  """  
  
  @behaviour Rtmp.Protocol.RawMessage
  @type t :: %__MODULE__{}
  
  defstruct parameters: []
  
  def deserialize(data) do
    {:ok, objects} = Amf0.deserialize(data)
    
    %__MODULE__{parameters: objects}
  end
  
  def serialize(%__MODULE__{parameters: params}) do   
    {:ok, Amf0.serialize(params)} 
  end
  
  def get_default_chunk_stream_id(%__MODULE__{}),  do: 3
end