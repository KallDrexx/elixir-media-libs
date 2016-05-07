defmodule RtmpCommon.Messages.SerializationTest do
  use ExUnit.Case, async: true
  
  test "Can convert abort message to serialized message" do
    message = %RtmpCommon.Messages.Types.Abort{stream_id: 525}
    
    expected = {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 2, 
      data: <<525::32>>}
    }
    
    assert expected == RtmpCommon.Messages.Types.Abort.serialize(message)
  end
  
  test "Can convert acknowledgement message to serialized message" do
    message = %RtmpCommon.Messages.Types.Acknowledgement{sequence_number: 9321}
    
    expected = {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 3,
      data: <<9321::32>>
    }}
    
    assert expected == RtmpCommon.Messages.Types.Acknowledgement.serialize(message)
  end 
  
  test "Can convert set chunk size message to serialized message" do
    message = %RtmpCommon.Messages.Types.SetChunkSize{size: 4096}
    
    expected = {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 1,
      data: <<0::1, 4096::31>>
    }}
    
    assert expected == RtmpCommon.Messages.Types.SetChunkSize.serialize(message)
  end 
  
  test "Can convert set peer bandwidth message to serialized message" do
    message = %RtmpCommon.Messages.Types.SetPeerBandwidth{
      window_size: 4096,
      limit_type: :soft
    }
    
    expected = {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 6,
      data: <<4096::32, 1::8>>
    }}
    
    assert expected == RtmpCommon.Messages.Types.SetPeerBandwidth.serialize(message)
  end 
  
  test "Can convert window acknowledgement size message to serialized message" do
    message = %RtmpCommon.Messages.Types.WindowAcknowledgementSize{
      size: 5022
    }
    
    expected = {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 5,
      data: <<5022::32>>
    }}
    
    assert expected == RtmpCommon.Messages.Types.WindowAcknowledgementSize.serialize(message)
  end
  
  test "Can convert user control stream begin message to serialized message" do
    message = %RtmpCommon.Messages.Types.UserControl{
      type: :stream_begin,
      stream_id: 500
    }
    
    expected = {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 4,
      data: <<0::16, 500::32>>
    }}
    
    assert expected == RtmpCommon.Messages.Types.UserControl.serialize(message)
  end
  
  test "Can convert user control stream eof message to serialized message" do
    message = %RtmpCommon.Messages.Types.UserControl{
      type: :stream_eof,
      stream_id: 501
    }
    
    expected = {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 4,
      data: <<1::16, 501::32>>
    }}
    
    assert expected == RtmpCommon.Messages.Types.UserControl.serialize(message)
  end
  
  test "Can convert user control stream dry message to serialized message" do
    message = %RtmpCommon.Messages.Types.UserControl{
      type: :stream_dry,
      stream_id: 502
    }
    
    expected = {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 4,
      data: <<2::16, 502::32>>
    }}
    
    assert expected == RtmpCommon.Messages.Types.UserControl.serialize(message)
  end
  
  test "Can convert user control set buffer length message to serialized message" do
    message = %RtmpCommon.Messages.Types.UserControl{
      type: :set_buffer_length,
      stream_id: 503,
      buffer_length: 100
    }
    
    expected = {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 4,
      data: <<3::16, 503::32, 100::32>>
    }}
    
    assert expected == RtmpCommon.Messages.Types.UserControl.serialize(message)
  end
  
  test "Can convert user control stream is recorded message to serialized message" do
    message = %RtmpCommon.Messages.Types.UserControl{
      type: :stream_is_recorded,
      stream_id: 504
    }
    
    expected = {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 4,
      data: <<4::16, 504::32>>
    }}
    
    assert expected == RtmpCommon.Messages.Types.UserControl.serialize(message)
  end
  
  test "Can convert user control ping request message to serialized message" do
    message = %RtmpCommon.Messages.Types.UserControl{
      type: :ping_request,
      timestamp: 506
    }
    
    expected = {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 4,
      data: <<6::16, 506::32>>
    }}
    
    assert expected == RtmpCommon.Messages.Types.UserControl.serialize(message)
  end
  
  test "Can convert user control ping response message to serialized message" do
    message = %RtmpCommon.Messages.Types.UserControl{
      type: :ping_response,
      timestamp: 507
    }
    
    expected = {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 4,
      data: <<7::16, 507::32>>
    }}
    
    assert expected == RtmpCommon.Messages.Types.UserControl.serialize(message)
  end
  
  test "Can convert amf 0 command message to serialized message" do
    amf_objects = [
      %RtmpCommon.Amf0.Object{type: :string, value: "something"},
      %RtmpCommon.Amf0.Object{type: :number, value: 1221},
      %RtmpCommon.Amf0.Object{type: :null, value: nil},
      %RtmpCommon.Amf0.Object{type: :string, value: "test"}
    ]
    
    expected = {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 20,
      data: RtmpCommon.Amf0.serialize(amf_objects) 
    }}
    
    message = %RtmpCommon.Messages.Types.Amf0Command{
      command_name: "something",
      transaction_id: 1221,
      command_object: %RtmpCommon.Amf0.Object{type: :null, value: nil},
      additional_values: [%RtmpCommon.Amf0.Object{type: :string, value: "test"}]
    }
    
    assert expected == RtmpCommon.Messages.Types.Amf0Command.serialize(message)
  end
end