defmodule RtmpSession.RtmpMessage do
  @moduledoc """
  Module that represents a raw RTMP message, and functions to unpack
  and repack them for handling and serialization
  """

  defstruct timestamp: nil,
            message_type_id: nil,
            payload: <<>>

  @callback parse(binary) :: any
  @callback serialize(struct()) :: {:ok, %__MODULE__{}}
  @callback get_default_chunk_stream_id(struct()) :: pos_integer()

  @doc "Unpacks the specified RTMP message into it's proper structure"
  @spec unpack(%__MODULE__{}) :: {:error, :unknown_message_type} | 
    {:ok, RtmpSession.Messages.SetChunkSize.t} |
    {:ok, RtmpSession.Messages.Abort.t} |
    {:ok, RtmpSession.Messages.Acknowledgement.t} |
    {:ok, RtmpSession.Messages.UserControl.t} |
    {:ok, RtmpSession.Messages.WindowAcknowledgementSize.t} |
    {:ok, RtmpSession.Messages.SetPeerBandwidth.t} |
    {:ok, RtmpSession.Messages.AudioData.t} |
    {:ok, RtmpSession.Messages.VideoData.t} |
    {:ok, RtmpSession.Messages.Amf0Command.t} |
    {:ok, RtmpSession.Messages.Amf0Data.t}

  def unpack(message = %__MODULE__{}) do
    case get_message_module(message.message_type_id) do
      nil -> {:error, :unknown_message_type}
      module -> {:ok, module.parse(message.payload)}
    end
  end
  
  defp get_message_module(1), do: RtmpSession.Messages.SetChunkSize
  defp get_message_module(2), do: RtmpSession.Messages.Abort
  defp get_message_module(3), do: RtmpSession.Messages.Acknowledgement
  defp get_message_module(4), do: RtmpSession.Messages.UserControl
  defp get_message_module(5), do: RtmpSession.Messages.WindowAcknowledgementSize
  defp get_message_module(6), do: RtmpSession.Messages.SetPeerBandwidth
  defp get_message_module(8), do: RtmpSession.Messages.AudioData
  defp get_message_module(9), do: RtmpSession.Messages.VideoData
  defp get_message_module(20), do: RtmpSession.Messages.Amf0Command
  defp get_message_module(18), do: RtmpSession.Messages.Amf0Data
  defp get_message_module(_), do: nil

end