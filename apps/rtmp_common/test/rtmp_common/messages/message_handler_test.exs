defmodule RtmpCommon.Messages.MessageHandlerTest do
  use ExUnit.Case, async: true
  alias RtmpCommon.Messages.Types, as: Types
  alias RtmpCommon.Amf0, as: Amf0
  
  defmodule InvalidMessage do
    defstruct something: nil
  end
   
  test "No handler returns type of message passed in" do
    expected = {:error, {:no_handler_for_message, InvalidMessage}}
    result = RtmpCommon.MessageHandler.handle(%InvalidMessage{}, %RtmpCommon.ConnectionDetails{})
    
    assert expected == result
  end
  
  test "Set chunk size message returns new chunk size and no response" do
    message = %Types.SetChunkSize{size: 4096}
    connection_details = %RtmpCommon.ConnectionDetails{peer_chunk_size: 128}    
    expected = {:ok, {%RtmpCommon.ConnectionDetails{peer_chunk_size: 4096}, nil}}
     
    assert expected == RtmpCommon.MessageHandler.handle(message, connection_details) 
  end
  
  test "Window Acknowledgement Size message returns peer size and no response" do
    message = %Types.WindowAcknowledgementSize{size: 5000}
    connection_details = %RtmpCommon.ConnectionDetails{peer_window_size: 0}    
    expected = {:ok, {%RtmpCommon.ConnectionDetails{peer_window_size: 5000}, nil}}
     
    assert expected == RtmpCommon.MessageHandler.handle(message, connection_details)
  end
  
  test "Amf0 connect command stores details and returns success response" do
    message = %Types.Amf0Command{
      command_name: "connect",
      transaction_id: 1,
      command_object: %Amf0.Object{type: :object, value: %{
        "app" => %Amf0.Object{type: :string, value: "myapp"}
      }}
    }
    
    connection_details = %RtmpCommon.ConnectionDetails{}
    result = RtmpCommon.MessageHandler.handle(message, connection_details)

    assert {:ok, {
        %RtmpCommon.ConnectionDetails{app_name: "myapp"},
        [%Types.Amf0Command{
          command_name: "_result",
          transaction_id: 1,
          command_object: %Amf0.Object{
              type: :object,
              value: %{
                "fmsVer" => %Amf0.Object{type: :string, value: <<_::binary>>},
                "capabilities" => %Amf0.Object{type: :number, value: 31}
              } 
            },
          additional_values: [
            %Amf0.Object{
              type: :object,
              value: %{
                "level" => %Amf0.Object{type: :string, value: "status"},
                "code" => %Amf0.Object{type: :string, value: "NetConnection.Connect.Success"},
                "description" => %Amf0.Object{type: :string, value: "Connection succeeded"},
                "objectEncoding" => %Amf0.Object{type: :number, value: 0}
              }
            }
          ]
        }],
      }
    } = result
  end

end