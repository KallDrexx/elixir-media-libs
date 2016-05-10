defmodule RtmpCommon.Messages.MessageHandlerTest do
  use ExUnit.Case, async: true
  
  defmodule InvalidMessage do
    defstruct something: nil
  end
   
  test "No handler returns type of message passed in" do
    expected = {:error, {:no_handler_for_message, InvalidMessage}}
    result = RtmpCommon.MessageHandler.handle(%InvalidMessage{}, %RtmpCommon.ConnectionDetails{})
    
    assert expected == result
  end
  
  test "Set chunk size message returns new chunk size and no response" do
    message = %RtmpCommon.Messages.Types.SetChunkSize{size: 4096}
    connection_Details = %RtmpCommon.ConnectionDetails{peer_chunk_size: 128}    
    expected = {:ok, {%RtmpCommon.ConnectionDetails{peer_chunk_size: 4096}, nil}}
     
    assert expected == RtmpCommon.MessageHandler.handle(message, connection_Details) 
  end
  
  test "Window Acknowledgement Size message returns peer size and no response" do
    message = %RtmpCommon.Messages.Types.WindowAcknowledgementSize{size: 5000}
    connection_Details = %RtmpCommon.ConnectionDetails{peer_window_size: 0}    
    expected = {:ok, {%RtmpCommon.ConnectionDetails{peer_window_size: 5000}, nil}}
     
    assert expected == RtmpCommon.MessageHandler.handle(message, connection_Details)
  end

end