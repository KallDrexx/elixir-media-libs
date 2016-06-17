defmodule RtmpSession.Messages.SetPeerBandwidth do
  @moduledoc """
  
  Sender is requesting the receiver limit its output
  bandwidth by limiting the amount of sent but
  unacknowledged data to the specified window size
  
  """
  
  defstruct window_size: 0, limit_type: nil
  
  @behaviour RtmpSession.RtmpMessage
  
  def parse(data) do
    <<size::32, type::8>> = data
    
    %__MODULE__{window_size: size, limit_type: get_friendly_type(type)}
  end
  
  def serialize(message = %__MODULE__{}) do
    type = case message.limit_type do
      :hard -> 0
      :soft -> 1
      :dynamic -> 2
    end
    
    {:ok, %RtmpSession.RtmpMessage{
      message_type_id: 6,
      payload: <<message.window_size::32, type::8>>
    }}
  end
  
  def get_default_chunk_stream_id(%__MODULE__{}),  do: 2
  
  defp get_friendly_type(0), do: :hard
  defp get_friendly_type(1), do: :soft
  defp get_friendly_type(2), do: :dynamic
end