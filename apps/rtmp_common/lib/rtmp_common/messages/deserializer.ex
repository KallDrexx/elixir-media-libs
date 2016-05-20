defmodule RtmpCommon.Messages.Deserializer do
  
  @doc "Deserializes the specified message into its respective structure"
  def deserialize(message_type_id, message_content) do
    case get_message_structure_type(message_type_id) do
      nil -> {:error, :unknown_message_type}
      module -> {:ok, module.parse(message_content)}
    end
  end
  
  defp get_message_structure_type(type_id) do
    [
      {1, RtmpCommon.Messages.Types.SetChunkSize},
      {2, RtmpCommon.Messages.Types.Abort},
      {3, RtmpCommon.Messages.Types.Acknowledgement},
      {4, RtmpCommon.Messages.Types.UserControl},
      {5, RtmpCommon.Messages.Types.WindowAcknowledgementSize},
      {6, RtmpCommon.Messages.Types.SetPeerBandwidth},
      {20, RtmpCommon.Messages.Types.Amf0Command}
    ]
    |> Map.new
    |> Map.get(type_id)
  end
end