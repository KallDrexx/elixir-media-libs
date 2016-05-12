defmodule RtmpCommon.MessageHandler do
  require Logger
  alias RtmpCommon.Messages.Types, as: Types
  alias RtmpCommon.ConnectionDetails, as: Details
  alias RtmpCommon.Amf0, as: Amf0
  
  @doc "Handles the specified message"
  def handle(message = %{__struct__: _}, details = %Details{}) do
    do_handle(message, details)
  end
  
  defp do_handle(message = %Types.SetChunkSize{}, connection_details = %Details{}) do
    updated_connection_details = %{connection_details | peer_chunk_size: message.size}
    {:ok, {updated_connection_details, nil}}
  end
  
  defp do_handle(%Types.WindowAcknowledgementSize{size: size}, connection_details = %Details{}) do
    updated_connection_details = %{connection_details | peer_window_size: size}
    {:ok, {updated_connection_details, nil}}
  end
  
  defp do_handle(command = %Types.Amf0Command{}, connection_details = %Details{}) do
    handle_amf0_command(command.transaction_id, command.command_name, command.command_object, command.additional_values, connection_details)
  end
  
  defp do_handle(%{__struct__: struct_type}, _connection_details = %Details{}) do
    {:error, {:no_handler_for_message, struct_type}}
  end
  
  defp handle_amf0_command(1, "connect", command_object, _, connection_details) do
    %Amf0.Object{type: :object, value: %{"app" => %Amf0.Object{type: :string, value: app}}} = command_object
    
    updated_connection_details = %{connection_details | app_name: app}
    {:ok, {updated_connection_details, [
      %Types.Amf0Command{
        command_name: "_result",
        transaction_id: 1,
        command_object: %Amf0.Object{
          type: :object,
          value: %{
            "fmsVer" => %Amf0.Object{type: :string, value: "FMS/3,0,1,123"},
            "capabilities" => %Amf0.Object{type: :number, value: 31}
          } 
        },
        additional_values: [
          %Amf0.Object{
            type: :object,
            value: %{
              "level" => %Amf0.Object{type: :string, value: "status"},
              "code" => %Amf0.Object{type: :string, value: "NetConnection.Connect.Success"},
              "description" => %Amf0.Object{type: :string, value: "Connection succeeded"},
              "objectEncoding" => %Amf0.Object{type: :number, value: 0}
            }
          }
        ]
      }
    ]}}
  end
  
  defp handle_amf0_command(transaction_id, command_name, _, _, _) do
    {:error, {:no_handler_for_command, command_name}}
  end
  
end