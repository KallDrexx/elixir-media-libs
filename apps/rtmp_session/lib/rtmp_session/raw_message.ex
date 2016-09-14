defmodule RtmpSession.RawMessage do
  @moduledoc """
  Module that represents a raw RTMP message, and functions to unpack
  and repack them for handling and serialization
  """

  alias RtmpSession.DetailedMessage, as: DetailedMessage

  @type t :: %__MODULE__{
    timestamp: non_neg_integer(),
    message_type_id: non_neg_integer(),
    stream_id: non_neg_integer(),
    payload: <<>>
  }

  defstruct timestamp: nil,
            message_type_id: nil,
            stream_id: nil,
            payload: <<>>

  @callback deserialize(binary) :: any
  @callback serialize(struct()) :: {:ok, <<>>}
  @callback get_default_chunk_stream_id(struct()) :: pos_integer()

  @doc "Unpacks the specified RTMP message into it's proper structure"
  @spec unpack(__MODULE__.t) :: {:error, :unknown_message_type} | {:ok, DetailedMessage.t}
  def unpack(message = %__MODULE__{}) do
    case get_message_module(message.message_type_id) do
      nil -> {:error, :unknown_message_type}
      module -> 
        {:ok, %RtmpSession.DetailedMessage{
          timestamp: message.timestamp,
          stream_id: message.stream_id,
          content: module.deserialize(message.payload)
        }}
    end
  end

  @doc "Packs a detailed RTMP message into a serializable raw message"
  @spec pack(DetailedMessage.t) :: __MODULE__.t
  def pack(message = %DetailedMessage{}) do
    %__MODULE__{
      timestamp: message.timestamp,
      stream_id: message.stream_id,
      message_type_id: get_message_type(message.content.__struct__),
      payload: message.content.__struct__.serialize(message.content)
    }
  end
  
  defp get_message_module(1), do: RtmpSession.Messages.SetChunkSize
  defp get_message_module(2), do: RtmpSession.Messages.Abort
  defp get_message_module(3), do: RtmpSession.Messages.Acknowledgement
  defp get_message_module(4), do: RtmpSession.Messages.UserControl
  defp get_message_module(5), do: RtmpSession.Messages.WindowAcknowledgementSize
  defp get_message_module(6), do: RtmpSession.Messages.SetPeerBandwidth
  defp get_message_module(8), do: RtmpSession.Messages.AudioData
  defp get_message_module(9), do: RtmpSession.Messages.VideoData
  defp get_message_module(18), do: RtmpSession.Messages.Amf0Data
  defp get_message_module(20), do: RtmpSession.Messages.Amf0Command
  defp get_message_module(_), do: nil

  # WARNING: We have to match on the module names themselves instead of
  # a normal struct pattern match, otherwise we have circular references
  # during compilation and it failes due to the callbacks
  defp get_message_type(RtmpSession.Messages.SetChunkSize), do: 1
  defp get_message_type(RtmpSession.Messages.Abort), do: 2
  defp get_message_type(RtmpSession.Messages.Acknowledgement), do: 3
  defp get_message_type(RtmpSession.Messages.UserControl), do: 4
  defp get_message_type(RtmpSession.Messages.WindowAcknowledgementSize), do: 5
  defp get_message_type(RtmpSession.Messages.SetPeerBandwidth), do: 6
  defp get_message_type(RtmpSession.Messages.AudioData), do: 8
  defp get_message_type(RtmpSession.Messages.VideoData), do: 9
  defp get_message_type(RtmpSession.Messages.Amf0Data), do: 18
  defp get_message_type(RtmpSession.Messages.Amf0Command), do: 20

end