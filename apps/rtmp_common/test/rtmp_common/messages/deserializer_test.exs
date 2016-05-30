defmodule RtmpCommon.Messages.DeserializerTest do
  use ExUnit.Case, async: true
  
  test "Can Parse SetChunkSize message" do
    {:ok, message} = RtmpCommon.Messages.Deserializer.deserialize(1, <<4000::32>>)
    
    assert %RtmpCommon.Messages.Types.SetChunkSize{size: 4000} = message
  end
  
  test "Can parse Abort message" do
    {:ok, message} = RtmpCommon.Messages.Deserializer.deserialize(2, <<500::32>>)
    
    assert %RtmpCommon.Messages.Types.Abort{stream_id: 500} = message
  end
  
  test "Can parse Acknowledgement message" do
    {:ok, message} = RtmpCommon.Messages.Deserializer.deserialize(3, <<25::32>>)
    
    assert %RtmpCommon.Messages.Types.Acknowledgement{sequence_number: 25} = message
  end
  
  test "Can parse Window Acknowlegement Size message" do
    {:ok, message} = RtmpCommon.Messages.Deserializer.deserialize(5, <<26::32>>)
    
    assert %RtmpCommon.Messages.Types.WindowAcknowledgementSize{size: 26} = message
  end
  
  test "Can parse Set Peer Bandwidth message" do
    {:ok, message} = RtmpCommon.Messages.Deserializer.deserialize(6, <<20::32, 1::8>>)
    
    assert %RtmpCommon.Messages.Types.SetPeerBandwidth{window_size: 20, limit_type: :soft} = message
  end
  
  test "Can parse User Control Stream Begin" do
    expected = %RtmpCommon.Messages.Types.UserControl{
      type: :stream_begin,
      stream_id: 521,
      buffer_length: nil,
      timestamp: nil
    }
    
    assert {:ok, expected} == RtmpCommon.Messages.Deserializer.deserialize(4, <<0::16, 521::32>>)
  end
  
  test "Can parse User Control Stream EOF" do
    expected = %RtmpCommon.Messages.Types.UserControl{
      type: :stream_eof,
      stream_id: 555,
      buffer_length: nil,
      timestamp: nil
    }
    
    assert {:ok, expected} == RtmpCommon.Messages.Deserializer.deserialize(4, <<1::16, 555::32>>)
  end
  
  test "Can parse User Control Stream Dry" do
    expected = %RtmpCommon.Messages.Types.UserControl{
      type: :stream_dry,
      stream_id: 666,
      buffer_length: nil,
      timestamp: nil
    }
    
    assert {:ok, expected} == RtmpCommon.Messages.Deserializer.deserialize(4, <<2::16, 666::32>>)
  end
  
  test "Can parse User Control Set Buffer Length" do
    expected = %RtmpCommon.Messages.Types.UserControl{
      type: :set_buffer_length,
      stream_id: 500,
      buffer_length: 300,
      timestamp: nil
    }
    
    assert {:ok, expected} == RtmpCommon.Messages.Deserializer.deserialize(4, <<3::16, 500::32, 300::32>>)
  end
  
  test "Can parse User Control Stream Is Recorded" do
    expected = %RtmpCommon.Messages.Types.UserControl{
      type: :stream_is_recorded,
      stream_id: 333,
      buffer_length: nil,
      timestamp: nil
    }
    
    assert {:ok, expected} == RtmpCommon.Messages.Deserializer.deserialize(4, <<4::16, 333::32>>)
  end
  
  test "Can parse User Control Ping Request" do
    expected = %RtmpCommon.Messages.Types.UserControl{
      type: :ping_request,
      stream_id: nil,
      buffer_length: nil,
      timestamp: 999
    }
    
    assert {:ok, expected} == RtmpCommon.Messages.Deserializer.deserialize(4, <<6::16, 999::32>>)
  end
  
  test "Can parse User Control Ping Response" do
    expected = %RtmpCommon.Messages.Types.UserControl{
      type: :ping_response,
      stream_id: nil,
      buffer_length: nil,
      timestamp: 900
    }
    
    assert {:ok, expected} == RtmpCommon.Messages.Deserializer.deserialize(4, <<7::16, 900::32>>)
  end
 
  test "Can parse amf 0 encoded command message" do
    expected = %RtmpCommon.Messages.Types.Amf0Command{
      command_name: "something",
      transaction_id: 1221,
      command_object: %RtmpCommon.Amf0.Object{type: :null, value: nil},
      additional_values: [%RtmpCommon.Amf0.Object{type: :string, value: "test"}]
    }
    
    amf_objects = [
      %RtmpCommon.Amf0.Object{type: :string, value: "something"},
      %RtmpCommon.Amf0.Object{type: :number, value: 1221},
      %RtmpCommon.Amf0.Object{type: :null, value: nil},
      %RtmpCommon.Amf0.Object{type: :string, value: "test"}
    ]
    
    binary = RtmpCommon.Amf0.serialize(amf_objects)
    
    assert {:ok, expected} == RtmpCommon.Messages.Deserializer.deserialize(20, binary)
  end
  
  test "Can parse amf0 encoded data message" do
    amf_objects = [
      %RtmpCommon.Amf0.Object{type: :string, value: "something"},
      %RtmpCommon.Amf0.Object{type: :number, value: 1221},
      %RtmpCommon.Amf0.Object{type: :null, value: nil},
      %RtmpCommon.Amf0.Object{type: :string, value: "test"}
    ]
    
    binary = RtmpCommon.Amf0.serialize(amf_objects)
    
    expected = %RtmpCommon.Messages.Types.Amf0Data{parameters: amf_objects}
    assert {:ok, expected} == RtmpCommon.Messages.Deserializer.deserialize(18, binary)
  end
  
  test "Can parse Video data message" do
    binary = <<1,2,3,4,5,6>>
    expected = %RtmpCommon.Messages.Types.VideoData{data: binary}
    assert {:ok, expected} == RtmpCommon.Messages.Deserializer.deserialize(9, binary)
  end
  
  test "Can parse Audio data message" do
    binary = <<1,2,3,4,5,6>>
    expected = %RtmpCommon.Messages.Types.AudioData{data: binary}
    assert {:ok, expected} == RtmpCommon.Messages.Deserializer.deserialize(8, binary)
  end
 
end