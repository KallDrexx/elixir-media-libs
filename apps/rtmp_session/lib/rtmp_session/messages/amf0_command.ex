defmodule RtmpSession.Messages.Amf0Command do
  @moduledoc """
  
  Message used to denote an amf0 encoded command (or resposne to a command)
  
  """
  
  @behaviour RtmpSession.RtmpMessage
  @type t :: %__MODULE__{}
  
  defstruct command_name: nil,
            transaction_id: nil,
            command_object: nil,
            additional_values: nil
  
  def deserialize(data) do
    {:ok, objects} = Amf0.deserialize(data)
    [command_name, transaction_id, command_object | rest] = objects

    %__MODULE__{
      command_name: command_name,
      transaction_id: transaction_id,
      command_object: command_object,
      additional_values: rest
    }
  end
  
  def serialize(message = %__MODULE__{}) do
    objects = [message.command_name, message.transaction_id, message.command_object | message.additional_values]
    binary = Amf0.serialize(objects)
    
    {:ok, %RtmpSession.RtmpMessage{
      message_type_id: 20,
      payload: binary
    }} 
  end
  
  def get_default_chunk_stream_id(%__MODULE__{}),  do: 3
end