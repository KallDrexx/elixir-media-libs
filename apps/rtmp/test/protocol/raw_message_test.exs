defmodule Rtmp.Protocol.RawMessageTest do
  use ExUnit.Case, async: true

  alias Rtmp.Protocol.RawMessage, as: RawMessage
  alias Rtmp.Protocol.DetailedMessage, as: RtmpDetailedMessage

  test "Can unpack SetChunkSize message" do
    rtmp_message = %RawMessage{message_type_id: 1, payload: <<4000::32>>}
    {:ok, message} = RawMessage.unpack(rtmp_message)
    
    assert %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.SetChunkSize{size: 4000}} = message
  end
  
  test "Can unpack Abort message" do
    rtmp_message = %RawMessage{message_type_id: 2, payload: <<500::32>>}
    {:ok, message} = RawMessage.unpack(rtmp_message)
    
    assert %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.Abort{stream_id: 500}} = message
  end
  
  test "Can unpack Acknowledgement message" do
    rtmp_message = %RawMessage{message_type_id: 3, payload: <<25::32>>}
    {:ok, message} = RawMessage.unpack(rtmp_message)
    
    assert %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.Acknowledgement{sequence_number: 25}} = message
  end
  
  test "Can unpack Window Acknowlegement Size message" do
    rtmp_message = %RawMessage{message_type_id: 5, payload: <<26::32>>}
    {:ok, message} = RawMessage.unpack(rtmp_message)
    
    assert %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.WindowAcknowledgementSize{size: 26}} = message
  end
  
  test "Can unpack Set Peer Bandwidth message" do
    rtmp_message = %RawMessage{message_type_id: 6, payload: <<20::32, 1::8>>}
    {:ok, message} = RawMessage.unpack(rtmp_message)
    
    assert %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.SetPeerBandwidth{window_size: 20, limit_type: :soft}} = message
  end
  
  test "Can unpack User Control Stream Begin" do
    expected = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.UserControl{
      type: :stream_begin,
      stream_id: 521,
      buffer_length: nil,
      timestamp: nil
    }}
    
    rtmp_message = %RawMessage{message_type_id: 4, payload: <<0::16, 521::32>>}
    assert {:ok, ^expected} = RawMessage.unpack(rtmp_message)
  end
  
  test "Can unpack User Control Stream EOF" do
    expected = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.UserControl{
      type: :stream_eof,
      stream_id: 555,
      buffer_length: nil,
      timestamp: nil
    }}    
    
    rtmp_message = %RawMessage{message_type_id: 4, payload: <<1::16, 555::32>>}
    assert {:ok, ^expected} = RawMessage.unpack(rtmp_message)
  end
  
  test "Can unpack User Control Stream Dry" do
    expected = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.UserControl{
      type: :stream_dry,
      stream_id: 666,
      buffer_length: nil,
      timestamp: nil
    }}
    
    rtmp_message = %RawMessage{message_type_id: 4, payload: <<2::16, 666::32>>}
    assert {:ok, ^expected} = RawMessage.unpack(rtmp_message)
  end
  
  test "Can unpack User Control Set Buffer Length" do
    expected = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.UserControl{
      type: :set_buffer_length,
      stream_id: 500,
      buffer_length: 300,
      timestamp: nil
    }}
    
    rtmp_message = %RawMessage{message_type_id: 4, payload: <<3::16, 500::32, 300::32>>}
    assert {:ok, ^expected} = RawMessage.unpack(rtmp_message)
  end
  
  test "Can unpack User Control Stream Is Recorded" do
    expected = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.UserControl{
      type: :stream_is_recorded,
      stream_id: 333,
      buffer_length: nil,
      timestamp: nil
    }}
    
    rtmp_message = %RawMessage{message_type_id: 4, payload: <<4::16, 333::32>>}
    assert {:ok, ^expected} = RawMessage.unpack(rtmp_message)
  end
  
  test "Can unpack User Control Ping Request" do
    expected = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.UserControl{
      type: :ping_request,
      stream_id: nil,
      buffer_length: nil,
      timestamp: 999
    }}
    
    rtmp_message = %RawMessage{message_type_id: 4, payload: <<6::16, 999::32>>}
    assert {:ok, ^expected} = RawMessage.unpack(rtmp_message)
  end
  
  test "Can unpack User Control Ping Response" do
    expected = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.UserControl{
      type: :ping_response,
      stream_id: nil,
      buffer_length: nil,
      timestamp: 900
    }}
    
    rtmp_message = %RawMessage{message_type_id: 4, payload: <<7::16, 900::32>>}
    assert {:ok, ^expected} = RawMessage.unpack(rtmp_message)
  end
 
  test "Can unpack amf 0 encoded command message" do
    expected = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.Amf0Command{
      command_name: "something",
      transaction_id: 1221.0,
      command_object: nil,
      additional_values: ["test"]
    }}
    
    amf_objects = ["something", 1221.0, nil, "test"]    
    binary = Amf0.serialize(amf_objects)
    
    rtmp_message = %RawMessage{message_type_id: 20, payload: binary}
    assert {:ok, ^expected} = RawMessage.unpack(rtmp_message)
  end
  
  test "Can unpack amf0 encoded data message" do
    amf_objects = ["something", 1221.0, nil, "test"]

    expected = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.Amf0Data{parameters: amf_objects}}
    binary = Amf0.serialize(amf_objects)

    rtmp_message = %RawMessage{message_type_id: 18, payload: binary}
    assert {:ok, ^expected} = RawMessage.unpack(rtmp_message)
  end
  
  test "Can unpack Video data message" do
    binary = <<1,2,3,4,5,6>>
    expected = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.VideoData{data: binary}}

    rtmp_message = %RawMessage{message_type_id: 9, payload: binary}
    assert {:ok, ^expected} = RawMessage.unpack(rtmp_message)
  end
  
  test "Can unpack Audio data message" do
    binary = <<1,2,3,4,5,6>>
    expected = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.AudioData{data: binary}}

    rtmp_message = %RawMessage{message_type_id: 8, payload: binary}
    assert {:ok, ^expected} = RawMessage.unpack(rtmp_message)
  end

  ## Detailed -> Raw tests (packing)

  test "Can convert SetChunkSize message to RawMessage" do
    message = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.SetChunkSize{size: 4000}}
    rtmp_message = RawMessage.pack(message)
    
    assert %RawMessage{message_type_id: 1, payload: <<4000::32>>} = rtmp_message
  end
  
  test "Can convert Abort message to RawMessage" do
    message = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.Abort{stream_id: 500}}
    rtmp_message = RawMessage.pack(message)
    
    assert %RawMessage{message_type_id: 2, payload: <<500::32>>} = rtmp_message
  end
  
  test "Can convert Acknowledgement message to RawMessage" do
    message = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.Acknowledgement{sequence_number: 25}}
    rtmp_message = RawMessage.pack(message)
    
    assert %RawMessage{message_type_id: 3, payload: <<25::32>>} = rtmp_message
  end
  
  test "Can convert Window Acknowlegement Size message to RawMessage" do
    message = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.WindowAcknowledgementSize{size: 26}}
    rtmp_message = RawMessage.pack(message)
    
    assert %RawMessage{message_type_id: 5, payload: <<26::32>>} = rtmp_message
  end
  
  test "Can convert Set Peer Bandwidth message to RawMessage" do
    message = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.SetPeerBandwidth{window_size: 20, limit_type: :soft}}
    rtmp_message = RawMessage.pack(message)
    
    assert %RawMessage{message_type_id: 6, payload: <<20::32, 1::8>>} = rtmp_message
  end
  
  test "Can convert User Control Stream Begin to RawMessage" do
    message = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.UserControl{
      type: :stream_begin,
      stream_id: 521,
      buffer_length: nil,
      timestamp: nil
    }}
    
    expected = %RawMessage{message_type_id: 4, payload: <<0::16, 521::32>>}
    assert ^expected = RawMessage.pack(message)
  end
  
  test "Can convert User Control Stream EOF to RawMessage" do
    message = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.UserControl{
      type: :stream_eof,
      stream_id: 555,
      buffer_length: nil,
      timestamp: nil
    }}    
    
    expected = %RawMessage{message_type_id: 4, payload: <<1::16, 555::32>>}
    assert ^expected = RawMessage.pack(message)
  end
  
  test "Can convert User Control Stream Dry to RawMessage" do
    message = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.UserControl{
      type: :stream_dry,
      stream_id: 666,
      buffer_length: nil,
      timestamp: nil
    }}
    
    expected = %RawMessage{message_type_id: 4, payload: <<2::16, 666::32>>}
    assert ^expected = RawMessage.pack(message)
  end
  
  test "Can convert User Control Set Buffer Length to RawMessage" do
    message = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.UserControl{
      type: :set_buffer_length,
      stream_id: 500,
      buffer_length: 300,
      timestamp: nil
    }}
    
    expected = %RawMessage{message_type_id: 4, payload: <<3::16, 500::32, 300::32>>}
    assert ^expected = RawMessage.pack(message)
  end
  
  test "Can convert User Control Stream Is Recorded to RawMessage" do
    message = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.UserControl{
      type: :stream_is_recorded,
      stream_id: 333,
      buffer_length: nil,
      timestamp: nil
    }}
    
    expected = %RawMessage{message_type_id: 4, payload: <<4::16, 333::32>>}
    assert ^expected = RawMessage.pack(message)
  end
  
  test "Can convert User Control Ping Request to RawMessage" do
    message = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.UserControl{
      type: :ping_request,
      stream_id: nil,
      buffer_length: nil,
      timestamp: 999
    }}
    
    expected = %RawMessage{message_type_id: 4, payload: <<6::16, 999::32>>}
    assert ^expected = RawMessage.pack(message)
  end
  
  test "Can convert User Control Ping Response to RawMessage" do
    message = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.UserControl{
      type: :ping_response,
      stream_id: nil,
      buffer_length: nil,
      timestamp: 900
    }}
    
    expected = %RawMessage{message_type_id: 4, payload: <<7::16, 900::32>>}
    assert ^expected = RawMessage.pack(message)
  end
 
  test "Can convert amf 0 encoded command message to RawMessage" do
    message = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.Amf0Command{
      command_name: "something",
      transaction_id: 1221.0,
      command_object: nil,
      additional_values: ["test"]
    }}
    
    amf_objects = ["something", 1221.0, nil, "test"]    
    binary = Amf0.serialize(amf_objects)
    
    expected = %RawMessage{message_type_id: 20, payload: binary}
    assert ^expected = RawMessage.pack(message)
  end
  
  test "Can convert amf0 encoded data message to RawMessage" do
    amf_objects = ["something", 1221.0, nil, "test"]

    message = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.Amf0Data{parameters: amf_objects}}
    binary = Amf0.serialize(amf_objects)

    expected = %RawMessage{message_type_id: 18, payload: binary}
    assert ^expected = RawMessage.pack(message)
  end
  
  test "Can convert Video data message to RawMessage" do
    binary = <<1,2,3,4,5,6>>
    message = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.VideoData{data: binary}}

    expected = %RawMessage{message_type_id: 9, payload: binary}
    assert ^expected = RawMessage.pack(message)
  end
  
  test "Can convert Audio data message to RawMessage" do
    binary = <<1,2,3,4,5,6>>
    message = %RtmpDetailedMessage{content: %Rtmp.Protocol.Messages.AudioData{data: binary}}

    expected = %RawMessage{message_type_id: 8, payload: binary}
    assert ^expected = RawMessage.pack(message)
  end

  test "Packing message transfers force uncompression flag when true" do
    message = %RtmpDetailedMessage{
      content: %Rtmp.Protocol.Messages.SetChunkSize{size: 4000},
      force_uncompressed: true
    }

    rtmp_message = RawMessage.pack(message)    
    assert %RawMessage{force_uncompressed: true} = rtmp_message
  end

  test "Packing message transfers force uncompression flag when false" do
    message = %RtmpDetailedMessage{
      content: %Rtmp.Protocol.Messages.SetChunkSize{size: 4000},
      force_uncompressed: false
    }

    rtmp_message = RawMessage.pack(message)    
    assert %RawMessage{force_uncompressed: false} = rtmp_message
  end
end