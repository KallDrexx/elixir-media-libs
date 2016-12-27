defmodule Rtmp.Protocol.RawMessage do
  @moduledoc """
  Module that represents a raw RTMP message, and functions to unpack
  and repack them for handling and serialization
  """

  alias Rtmp.Protocol.DetailedMessage, as: DetailedMessage

  @type t :: %__MODULE__{
    timestamp: non_neg_integer(),
    message_type_id: non_neg_integer(),
    stream_id: non_neg_integer(),
    force_uncompressed: false,
    deserialization_system_time: pos_integer(),
    payload: <<>>
  }

  defstruct timestamp: nil,
            message_type_id: nil,
            stream_id: nil,
            force_uncompressed: false,
            deserialization_system_time: nil,
            payload: <<>>

  @callback deserialize(binary) :: any
  @callback serialize(struct()) :: {:ok, binary()}
  @callback get_default_chunk_stream_id(struct()) :: pos_integer()

  @doc "Unpacks the specified RTMP message into it's proper structure"
  @spec unpack(__MODULE__.t) :: {:error, :unknown_message_type} | {:ok, DetailedMessage.t}
  def unpack(message = %__MODULE__{}) do
    case get_message_module(message.message_type_id) do
      nil -> {:error, :unknown_message_type}
      module -> 
        {:ok, %DetailedMessage{
          timestamp: message.timestamp,
          stream_id: message.stream_id,
          content: module.deserialize(message.payload),
          deserialization_system_time: message.deserialization_system_time
        }}
    end
  end

  @doc "Packs a detailed RTMP message into a serializable raw message"
  @spec pack(DetailedMessage.t) :: __MODULE__.t
  def pack(message = %DetailedMessage{}) do
    {:ok, payload} = message.content.__struct__.serialize(message.content)

    %__MODULE__{
      timestamp: message.timestamp,
      stream_id: message.stream_id,
      message_type_id: get_message_type(message.content.__struct__),
      payload: payload,
      force_uncompressed: message.force_uncompressed
    }
  end
  
  defp get_message_module(1), do: Rtmp.Protocol.Messages.SetChunkSize
  defp get_message_module(2), do: Rtmp.Protocol.Messages.Abort
  defp get_message_module(3), do: Rtmp.Protocol.Messages.Acknowledgement
  defp get_message_module(4), do: Rtmp.Protocol.Messages.UserControl
  defp get_message_module(5), do: Rtmp.Protocol.Messages.WindowAcknowledgementSize
  defp get_message_module(6), do: Rtmp.Protocol.Messages.SetPeerBandwidth
  defp get_message_module(8), do: Rtmp.Protocol.Messages.AudioData
  defp get_message_module(9), do: Rtmp.Protocol.Messages.VideoData
  defp get_message_module(18), do: Rtmp.Protocol.Messages.Amf0Data
  defp get_message_module(20), do: Rtmp.Protocol.Messages.Amf0Command

  # I have no idea why but AMF3 messages are actually internally encoded
  # in AMF0, so just use amf0 for decoding
  defp get_message_module(17), do: Rtmp.Protocol.Messages.Amf0Command
  defp get_message_module(15), do: Rtmp.Protocol.Messages.Amf0Data

  defp get_message_module(_), do: nil

  # WARNING: We have to match on the module names themselves instead of
  # a normal struct pattern match, otherwise we have circular references
  # during compilation and it failes due to the callbacks
  defp get_message_type(Rtmp.Protocol.Messages.SetChunkSize), do: 1
  defp get_message_type(Rtmp.Protocol.Messages.Abort), do: 2
  defp get_message_type(Rtmp.Protocol.Messages.Acknowledgement), do: 3
  defp get_message_type(Rtmp.Protocol.Messages.UserControl), do: 4
  defp get_message_type(Rtmp.Protocol.Messages.WindowAcknowledgementSize), do: 5
  defp get_message_type(Rtmp.Protocol.Messages.SetPeerBandwidth), do: 6
  defp get_message_type(Rtmp.Protocol.Messages.AudioData), do: 8
  defp get_message_type(Rtmp.Protocol.Messages.VideoData), do: 9
  defp get_message_type(Rtmp.Protocol.Messages.Amf0Data), do: 18
  defp get_message_type(Rtmp.Protocol.Messages.Amf0Command), do: 20

end