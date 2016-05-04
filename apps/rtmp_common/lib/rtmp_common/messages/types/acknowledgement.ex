defmodule RtmpCommon.Messages.Types.Acknowledgement do
  @moduledoc """
    
  Sent when the client or the server receives bytes equal to the window
  size.
  
  Contains the number of bytes received so far (sequence number)
  
  """
  
  @behaviour RtmpCommon.Messages.Message
  
  defstruct sequence_number: 0
  
  def parse(data) do
    <<sequence_number::32>> = data
    
    %__MODULE__{sequence_number: sequence_number}
  end
  
  def serialize(message = %__MODULE__{}) do
    {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 3,
      data: <<message.sequence_number::32>>
    }}
  end
end