defmodule RtmpCommon.Messages.Deserializer do
  
  @doc "Deserializes the specified message into its respective structure"
  def deserialize(message_type_id, message_content) do
    case get_message_structure_type(message_type_id) do
      nil -> {:error, :unknown_message_type}
      module -> {:ok, module.parse(message_content)}
    end
  end
  
  defp get_message_structure_type(1), do: RtmpCommon.Messages.Types.SetChunkSize
  defp get_message_structure_type(2), do: RtmpCommon.Messages.Types.Abort
  defp get_message_structure_type(3), do: RtmpCommon.Messages.Types.Acknowledgement
  defp get_message_structure_type(4), do: RtmpCommon.Messages.Types.UserControl
  defp get_message_structure_type(5), do: RtmpCommon.Messages.Types.WindowAcknowledgementSize
  defp get_message_structure_type(6), do: RtmpCommon.Messages.Types.SetPeerBandwidth
  defp get_message_structure_type(8), do: RtmpCommon.Messages.Types.AudioData
  defp get_message_structure_type(9), do: RtmpCommon.Messages.Types.VideoData
  defp get_message_structure_type(20), do: RtmpCommon.Messages.Types.Amf0Command
  defp get_message_structure_type(18), do: RtmpCommon.Messages.Types.Amf0Data
  defp get_message_structure_type(_), do: nil
  
end