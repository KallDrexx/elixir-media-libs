defmodule RtmpCommon.Messages.HandlerTest do
  use ExUnit.Case, async: true
  alias RtmpCommon.Messages.Types, as: Types
  alias RtmpCommon.Messages, as: Messages
  alias RtmpCommon.Amf0, as: Amf0
  
  setup do
    {handler, _} =
      RtmpCommon.Messages.Handler.new("abc")
      |> RtmpCommon.Messages.Handler.get_responses()
      
    {:ok, handler: handler}
  end
  
  test "New handler queues up window acknowledgement size message" do
    {_, responses} =
      RtmpCommon.Messages.Handler.new("abc")
      |> RtmpCommon.Messages.Handler.get_responses()
      
    message = Enum.find(responses, 
      fn(x) -> match?(%Messages.Response{message: %Types.WindowAcknowledgementSize{}}, x) end
    )      
    
    assert %Messages.Response{
      stream_id: 0,
      force_uncompressed: true,
      message: %Types.WindowAcknowledgementSize{}
    } = message
  end
  
  test "New handler queues up set chunk size message" do
    {_, responses} =
      RtmpCommon.Messages.Handler.new("abc")
      |> RtmpCommon.Messages.Handler.get_responses()
      
    message = Enum.find(responses, 
      fn(x) -> match?(%Messages.Response{message: %Types.SetChunkSize{}}, x) end
    )      
    
    assert %Messages.Response{
      stream_id: 0,
      force_uncompressed: true,
      message: %Types.SetChunkSize{}
    } = message
  end
  
  test "New handler queues up set peer bandwidth message" do
    {_, responses} =
      RtmpCommon.Messages.Handler.new("abc")
      |> RtmpCommon.Messages.Handler.get_responses()
      
    message = Enum.find(responses, 
      fn(x) -> match?(%Messages.Response{message: %Types.SetPeerBandwidth{}}, x) end
    )      
    
    assert %Messages.Response{
      stream_id: 0,
      force_uncompressed: true,
      message: %Types.SetPeerBandwidth{}
    } = message
  end
  
  test "New handler queues up user control stream begin" do
    {_, responses} =
      RtmpCommon.Messages.Handler.new("abc")
      |> RtmpCommon.Messages.Handler.get_responses()
      
    message = Enum.find(responses, 
      fn(x) -> match?(%Messages.Response{message: %Types.UserControl{}}, x) end
    )      
    
    assert %Messages.Response{
      stream_id: 0,
      message: %Types.UserControl{
        type: :stream_begin,
        stream_id: 0
      }
    } = message
  end
  
  test "Getting responses clears response state" do
    {handler, _} =
      RtmpCommon.Messages.Handler.new("abc")
      |> RtmpCommon.Messages.Handler.get_responses()
      
      assert {_, []} = RtmpCommon.Messages.Handler.get_responses(handler)
  end
  
  test "Ack response queued when byte received value over window", %{handler: handler} do
    ack_size = %Types.WindowAcknowledgementSize{size: 5000}
    
    {_, [message]} =
      RtmpCommon.Messages.Handler.handle(handler, ack_size)
      |> RtmpCommon.Messages.Handler.set_bytes_received(5001)
      |> RtmpCommon.Messages.Handler.get_responses()
      
    assert %Messages.Response{
      stream_id: 0,
      message: %Types.Acknowledgement{sequence_number: 5001}
    } = message
  end
  
  test "No Ack response queued when byte received under window", %{handler: handler} do
    ack_size = %RtmpCommon.Messages.Types.WindowAcknowledgementSize{size: 5000}
    
    {_, []} =
      RtmpCommon.Messages.Handler.handle(handler, ack_size)
      |> RtmpCommon.Messages.Handler.set_bytes_received(4999)
      |> RtmpCommon.Messages.Handler.get_responses()
  end
  
  test "Connect message returns response", %{handler: handler} do
    message = %Types.Amf0Command{
      command_name: "connect",
      transaction_id: 1,
      command_object: %Amf0.Object{type: :object, value: %{
        "app" => %Amf0.Object{type: :string, value: "myapp"}
      }}
    }
    
    {_, [message | _]} =
      RtmpCommon.Messages.Handler.handle(handler, message)
      |> RtmpCommon.Messages.Handler.get_responses()
      
    assert %Messages.Response{
      stream_id: 0,
      message: %Types.Amf0Command{
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
      }
    } = message
  end
  
  test "CreateStream message can be handled", %{handler: handler} do
    message = %Types.Amf0Command{
      command_name: "createStream",
      transaction_id: 5,
      command_object: %Amf0.Object{type: :null}
    }
    
    {_, [response | _]} =
      RtmpCommon.Messages.Handler.handle(handler, message)
      |> RtmpCommon.Messages.Handler.get_responses()
      
    assert %Messages.Response{
      stream_id: 0,
      message: %Types.Amf0Command{
        command_name: "_result",
        transaction_id: 5,
        command_object: %Amf0.Object{type: :null},
        additional_values: [
          %Amf0.Object{type: :number, value: 1}
        ]
      }
    } = response
  end
  
  test "Publish live command can be handled", %{handler: handler} do
    message = %Types.Amf0Command{
      command_name: "publish",
      transaction_id: 394,
      command_object: %Amf0.Object{type: :null},
      additional_values: [
        %Amf0.Object{type: :string, value: "test-stream"},
        %Amf0.Object{type: :string, value: "live"}
      ]
    }
    
    {_, [response | _]} =
      RtmpCommon.Messages.Handler.handle(handler, message)
      |> RtmpCommon.Messages.Handler.get_responses()
    
    assert %Messages.Response{
      stream_id: 0,
      message: %Types.Amf0Command{
        command_name: "onStatus",
        transaction_id: 0,
        command_object: %Amf0.Object{type: :null},
        additional_values: [
          %Amf0.Object{type: :object, value: %{
            "level" => %Amf0.Object{type: :string, value: "status"},
            "code" => %Amf0.Object{type: :string, value: "NetStream.Publish.Start"},
            "description" => %Amf0.Object{type: :string, value: "Stream 'test-stream' is now published."}
          }}
        ]
      }
    } = response
  end
end