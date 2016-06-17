defmodule RtmpSession.Messages.UserControl do
  @moduledoc """
  
  Message to notify the peer about user control events
  
  """
  
  @behaviour RtmpSession.RtmpMessage
  @type t :: %__MODULE__{}
  
  defstruct type: nil,
      stream_id: nil,
      buffer_length: nil,
      timestamp: nil
  
  def parse(data) do
    <<event_type::16, rest::binary>> = data
    
    parse(event_type, rest)
  end
  
  def serialize(message = %__MODULE__{}) do
    {:ok, %RtmpSession.RtmpMessage{
      message_type_id: 4,
      payload: serialize_data(message)
    }}
  end
  
  def get_default_chunk_stream_id(%__MODULE__{}),  do: 2
  
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
  
  defp serialize_data(%__MODULE__{type: :stream_begin, stream_id: stream_id}) do
    <<0::16, stream_id::32>>
  end
  
  defp serialize_data(%__MODULE__{type: :stream_eof, stream_id: stream_id}) do
    <<1::16, stream_id::32>>
  end
  
  defp serialize_data(%__MODULE__{type: :stream_dry, stream_id: stream_id}) do
    <<2::16, stream_id::32>>
  end
  
  defp serialize_data(%__MODULE__{type: :set_buffer_length, stream_id: stream_id, buffer_length: buffer_length}) do
    <<3::16, stream_id::32, buffer_length::32>>
  end
  
  defp serialize_data(%__MODULE__{type: :stream_is_recorded, stream_id: stream_id}) do
    <<4::16, stream_id::32>>
  end
  
  defp serialize_data(%__MODULE__{type: :ping_request, timestamp: timestamp}) do
    <<6::16, timestamp::32>>
  end
  
  defp serialize_data(%__MODULE__{type: :ping_response, timestamp: timestamp}) do
    <<7::16, timestamp::32>>
  end
  
end