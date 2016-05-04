defmodule RtmpCommon.Messages.Types.UserControl do
  @moduledoc """
  
  Message to notify the peer about user control events
  
  """
  
  @behaviour RtmpCommon.Messages.Message
  
  defstruct type: nil,
      stream_id: nil,
      buffer_length: nil,
      timestamp: nil
  
  def parse(data) do
    <<event_type::16, rest::binary>> = data
    
    parse(event_type, rest)
  end
  
  def serialize(message = %__MODULE__{}) do
    {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 2,
      data: <<message.stream_id::size(4)-unit(8)>>
    }}
  end
  
  defp parse(0, data) do
    <<stream_id::32>> = data
    %__MODULE__{type: :stream_begin, stream_id: stream_id}
  end
  
  defp parse(1, data) do
    <<stream_id::32>> = data
    %__MODULE__{type: :stream_eof, stream_id: stream_id}
  end
  
  defp parse(2, data) do
    <<stream_id::32>> = data
    %__MODULE__{type: :stream_dry, stream_id: stream_id}
  end
  
  defp parse(3, data) do
    <<stream_id::32, buffer_length::32>> = data
    %__MODULE__{type: :set_buffer_length, stream_id: stream_id, buffer_length: buffer_length}
  end
  
  defp parse(4, data) do
    <<stream_id::32>> = data
    %__MODULE__{type: :stream_is_recorded, stream_id: stream_id}
  end
  
  defp parse(6, data) do
    <<timestamp::32>> = data
    %__MODULE__{type: :ping_request, timestamp: timestamp}
  end
  
  defp parse(7, data) do
    <<timestamp::32>> = data
    %__MODULE__{type: :ping_response, timestamp: timestamp}
  end
  
end