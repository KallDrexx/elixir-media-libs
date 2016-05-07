defmodule RtmpCommon.Messages.Types.Amf0Command do
  @moduledoc """
  
  Message used to denote an amf0 encoded command (or resposne to a command)
  
  """
  
  @behaviour RtmpCommon.Messages.Message
  
  defstruct command_name: nil,
            transaction_id: nil,
            command_object: nil,
            additional_values: nil
  
  def parse(data) do
    objects = RtmpCommon.Amf0.deserialize(data)
    
    populate_command(:command_name, objects, %RtmpCommon.Messages.Types.Amf0Command{})
  end
  
  def serialize(message = %__MODULE__{}) do
    binary = get_object_array(:command_name, message, []) |> RtmpCommon.Amf0.serialize
    
    {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 20,
      data: binary
    }} 
  end
  
  defp populate_command(_, [], command) do
    command
  end
  
  defp populate_command(:command_name, [%RtmpCommon.Amf0.Object{type: :string, value: name} | rest], command) do
    populate_command(:transaction_id, rest, %{command | command_name: name})
  end
  
  defp populate_command(:transaction_id, [%RtmpCommon.Amf0.Object{type: :number, value: number} | rest], command) do
    populate_command(:command_object, rest, %{command | transaction_id: number})
  end
  
  defp populate_command(:command_object, [ object = %RtmpCommon.Amf0.Object{} | rest], command) do
    %{command | command_object: object, additional_values: rest}
  end
  
  defp get_object_array(:command_name, command, accumulator) do
    get_object_array(:transaction_id, command, [create_amf0_object(command.command_name) | accumulator])
  end
  
  defp get_object_array(:transaction_id, command, accumulator) do
    get_object_array(:command_object, command, [create_amf0_object(command.transaction_id) | accumulator])
  end
  
  defp get_object_array(:command_object, command, accumulator) do
    command_object = case command.command_object do
      nil -> create_amf0_object(nil)
      x = %RtmpCommon.Amf0.Object{} -> x
      x -> create_amf0_object(x)
    end
    
    [command_object | accumulator]
    |> Enum.reverse
    |> Enum.concat(command.additional_values)
  end
  
  defp create_amf0_object(nil) do
    %RtmpCommon.Amf0.Object{type: :null, value: nil}
  end
  
  defp create_amf0_object(string) when is_binary(string) do
    %RtmpCommon.Amf0.Object{type: :string, value: string}
  end
  
  defp create_amf0_object(number) when is_number(number) do
    %RtmpCommon.Amf0.Object{type: :number, value: number}
  end
end