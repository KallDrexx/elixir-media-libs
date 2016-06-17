defmodule RtmpSession.Messages.Acknowledgement do
  @moduledoc """
    
  Sent when the client or the server receives bytes equal to the window
  size.
  
  Contains the number of bytes received so far (sequence number)
  
  """
  
  @behaviour RtmpSession.RtmpMessage
  @type t :: %__MODULE__{}
  
  defstruct sequence_number: 0
  
  def parse(data) do
    <<sequence_number::32>> = data
    
    %__MODULE__{sequence_number: sequence_number}
  end
  
  def serialize(message = %__MODULE__{}) do
    {:ok, %RtmpSession.RtmpMessage{
      message_type_id: 3,
      payload: <<message.sequence_number::32>>
    }}
  end
  
  def get_default_chunk_stream_id(%__MODULE__{}),  do: 2
end