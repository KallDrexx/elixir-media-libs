defmodule RtmpSession.RtmpMessageTest do
  use ExUnit.Case, async: true
  alias RtmpSession.RtmpMessage, as: RtmpMessage

  test "Can unpack SetChunkSize message" do
    rtmp_message = %RtmpMessage{message_type_id: 1, payload: <<4000::32>>}
    {:ok, message} = RtmpMessage.unpack(rtmp_message)
    
    assert %RtmpSession.Messages.SetChunkSize{size: 4000} = message
  end
  
  test "Can unpack Abort message" do
    rtmp_message = %RtmpMessage{message_type_id: 2, payload: <<500::32>>}
    {:ok, message} = RtmpMessage.unpack(rtmp_message)
    
    assert %RtmpSession.Messages.Abort{stream_id: 500} = message
  end
  
  test "Can unpack Acknowledgement message" do
    rtmp_message = %RtmpMessage{message_type_id: 3, payload: <<25::32>>}
    {:ok, message} = RtmpMessage.unpack(rtmp_message)
    
    assert %RtmpSession.Messages.Acknowledgement{sequence_number: 25} = message
  end
  
  test "Can unpack Window Acknowlegement Size message" do
    rtmp_message = %RtmpMessage{message_type_id: 5, payload: <<26::32>>}
    {:ok, message} = RtmpMessage.unpack(rtmp_message)
    
    assert %RtmpSession.Messages.WindowAcknowledgementSize{size: 26} = message
  end
  
  test "Can unpack Set Peer Bandwidth message" do
    rtmp_message = %RtmpMessage{message_type_id: 6, payload: <<20::32, 1::8>>}
    {:ok, message} = RtmpMessage.unpack(rtmp_message)
    
    assert %RtmpSession.Messages.SetPeerBandwidth{window_size: 20, limit_type: :soft} = message
  end
  
  test "Can unpack User Control Stream Begin" do
    expected = %RtmpSession.Messages.UserControl{
      type: :stream_begin,
      stream_id: 521,
      buffer_length: nil,
      timestamp: nil
    }
    
    rtmp_message = %RtmpMessage{message_type_id: 4, payload: <<0::16, 521::32>>}
    assert {:ok, expected} == RtmpMessage.unpack(rtmp_message)
  end
  
  test "Can unpack User Control Stream EOF" do
    expected = %RtmpSession.Messages.UserControl{
      type: :stream_eof,
      stream_id: 555,
      buffer_length: nil,
      timestamp: nil
    }    
    
    rtmp_message = %RtmpMessage{message_type_id: 4, payload: <<1::16, 555::32>>}
    assert {:ok, expected} == RtmpMessage.unpack(rtmp_message)
  end
  
  test "Can unpack User Control Stream Dry" do
    expected = %RtmpSession.Messages.UserControl{
      type: :stream_dry,
      stream_id: 666,
      buffer_length: nil,
      timestamp: nil
    }
    
    rtmp_message = %RtmpMessage{message_type_id: 4, payload: <<2::16, 666::32>>}
    assert {:ok, expected} == RtmpMessage.unpack(rtmp_message)
  end
  
  test "Can unpack User Control Set Buffer Length" do
    expected = %RtmpSession.Messages.UserControl{
      type: :set_buffer_length,
      stream_id: 500,
      buffer_length: 300,
      timestamp: nil
    }
    
    rtmp_message = %RtmpMessage{message_type_id: 4, payload: <<3::16, 500::32, 300::32>>}
    assert {:ok, expected} == RtmpMessage.unpack(rtmp_message)
  end
  
  test "Can unpack User Control Stream Is Recorded" do
    expected = %RtmpSession.Messages.UserControl{
      type: :stream_is_recorded,
      stream_id: 333,
      buffer_length: nil,
      timestamp: nil
    }
    
    rtmp_message = %RtmpMessage{message_type_id: 4, payload: <<4::16, 333::32>>}
    assert {:ok, expected} == RtmpMessage.unpack(rtmp_message)
  end
  
  test "Can unpack User Control Ping Request" do
    expected = %RtmpSession.Messages.UserControl{
      type: :ping_request,
      stream_id: nil,
      buffer_length: nil,
      timestamp: 999
    }
    
    rtmp_message = %RtmpMessage{message_type_id: 4, payload: <<6::16, 999::32>>}
    assert {:ok, expected} == RtmpMessage.unpack(rtmp_message)
  end
  
  test "Can unpack User Control Ping Response" do
    expected = %RtmpSession.Messages.UserControl{
      type: :ping_response,
      stream_id: nil,
      buffer_length: nil,
      timestamp: 900
    }
    
    rtmp_message = %RtmpMessage{message_type_id: 4, payload: <<7::16, 900::32>>}
    assert {:ok, expected} == RtmpMessage.unpack(rtmp_message)
  end
 
  test "Can unpack amf 0 encoded command message" do
    expected = %RtmpSession.Messages.Amf0Command{
      command_name: "something",
      transaction_id: 1221,
      command_object: nil,
      additional_values: ["test"]
    }
    
    amf_objects = ["something", 1221.0, nil, "test"]    
    binary = Amf0.serialize(amf_objects)
    
    rtmp_message = %RtmpMessage{message_type_id: 20, payload: binary}
    assert {:ok, expected} == RtmpMessage.unpack(rtmp_message)
  end
  
  test "Can unpack amf0 encoded data message" do
    amf_objects = ["something", 1221.0, nil, "test"]

    expected = %RtmpSession.Messages.Amf0Data{parameters: amf_objects}
    binary = Amf0.serialize(amf_objects)

    rtmp_message = %RtmpMessage{message_type_id: 18, payload: binary}
    assert {:ok, expected} == RtmpMessage.unpack(rtmp_message)
  end
  
  test "Can unpack Video data message" do
    binary = <<1,2,3,4,5,6>>
    expected = %RtmpSession.Messages.VideoData{data: binary}

    rtmp_message = %RtmpMessage{message_type_id: 9, payload: binary}
    assert {:ok, expected} == RtmpMessage.unpack(rtmp_message)
  end
  
  test "Can unpack Audio data message" do
    binary = <<1,2,3,4,5,6>>
    expected = %RtmpSession.Messages.AudioData{data: binary}

    rtmp_message = %RtmpMessage{message_type_id: 8, payload: binary}
    assert {:ok, expected} == RtmpMessage.unpack(rtmp_message)
  end
end