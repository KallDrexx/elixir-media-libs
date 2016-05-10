defmodule RtmpCommon.MessageHandler do
  require Logger
  alias RtmpCommon.Messages.Types, as: Types
  alias RtmpCommon.ConnectionDetails, as: Details
  
  @doc "Handles the specified message"
  def handle(message = %{__struct__: _}, details = %Details{}) do
    do_handle(message, details)
  end
  
  def do_handle(message = %Types.SetChunkSize{}, connection_details = %Details{}) do
    updated_connection_details = %{connection_details | peer_chunk_size: message.size}
    {:ok, {updated_connection_details, nil}}
  end
  
  def do_handle(%Types.WindowAcknowledgementSize{size: size}, connection_details = %Details{}) do
    updated_connection_details = %{connection_details | peer_window_size: size}
    {:ok, {updated_connection_details, nil}}
  end
  
  def do_handle(%{__struct__: struct_type}, _connection_details = %Details{}) do
    {:error, {:no_handler_for_message, struct_type}}
  end
  
end