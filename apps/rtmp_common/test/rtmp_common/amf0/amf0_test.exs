defmodule RtmpCommon.Amf0.Amf0Test do
  use ExUnit.Case, async: true
  
  test "Can deserialize number" do
    binary = <<0::8, 532::64>>
    expected = [%RtmpCommon.Amf0.Object{type: :number, value: 532}]
    
    assert expected == RtmpCommon.Amf0.deserialize(binary)
  end
  
  test "Can serialize number" do
    object = %RtmpCommon.Amf0.Object{type: :number, value: 332}
    expected = <<0::8, 332::64>>
    
    assert expected == RtmpCommon.Amf0.serialize(object)
  end
  
  test "Can deserialize boolean" do
    binary = <<1::8, 1::8>>
    expected = [%RtmpCommon.Amf0.Object{type: :boolean, value: true}]
    
    assert expected == RtmpCommon.Amf0.deserialize(binary)
  end
  
  test "Can serialize boolean" do
    object = %RtmpCommon.Amf0.Object{type: :boolean, value: true}
    expected = <<1::8, 1::8>>
    
    assert expected == RtmpCommon.Amf0.serialize(object)
  end
  
  test "Can deserialize UTF8-1 string" do
    binary = <<2::8, 4::16>> <> "test"
    expected = [%RtmpCommon.Amf0.Object{type: :string, value: "test"}]
    
    assert expected == RtmpCommon.Amf0.deserialize(binary)
  end
  
  test "Can serialize UTF8-1 string" do
    object = %RtmpCommon.Amf0.Object{type: :string, value: "test"}
    expected = <<2::8, 4::16>> <> "test"
    
    assert expected == RtmpCommon.Amf0.serialize(object)
  end
  
  test "Can deserialize object" do
    binary = <<3::8, 4::16>> <> "test" <> <<2::8, 5::16>> <> "value" <> <<0, 0, 9>>
    expected = [%RtmpCommon.Amf0.Object{
      type: :object,
      value: %{"test" => %RtmpCommon.Amf0.Object{type: :string, value: "value"}}
    }]
    
    assert expected == RtmpCommon.Amf0.deserialize(binary)
  end
  
  test "Can serialize object" do
    object = %RtmpCommon.Amf0.Object{
      type: :object,
      value: %{"test" => %RtmpCommon.Amf0.Object{type: :string, value: "value"}}
    }
    
    expected = <<3::8, 4::16>> <> "test" <> <<2::8, 5::16>> <> "value" <> <<0, 0, 9>>
    
    assert expected == RtmpCommon.Amf0.serialize(object)
  end
  
  test "Can deserialize consecutive values" do
    binary = <<0::8, 532::64, 1::8, 1::8>>
    expected = [
      %RtmpCommon.Amf0.Object{type: :number, value: 532},
      %RtmpCommon.Amf0.Object{type: :boolean, value: true}
    ]
    
    assert expected == RtmpCommon.Amf0.deserialize(binary)
  end
  
  test "Can serialize multiple values" do
    objects = [
      %RtmpCommon.Amf0.Object{type: :number, value: 532},
      %RtmpCommon.Amf0.Object{type: :boolean, value: true}
    ]
    expected = <<0::8, 532::64, 1::8, 1::8>>
    
    assert expected == RtmpCommon.Amf0.serialize(objects)
  end
  
  test "Can deserialize object with multiple properties (rtmp connect object)" do
    binary = <<0x03, 0x00, 0x03, 0x61, 0x70, 0x70, 0x02, 0x00, 0x04, 0x6c, 0x69, 0x76, 0x65, 0x00, 0x04, 0x74, 0x79, 0x70, 0x65, 0x02, 0x00, 0x0a, 0x6e, 0x6f, 0x6e, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x00, 0x08, 0x66, 0x6c, 0x61, 0x73, 0x68, 0x56, 0x65, 0x72, 0x02, 0x00, 0x1f, 0x46, 0x4d, 0x4c, 0x45, 0x2f, 0x33, 0x2e, 0x30, 0x20, 0x28, 0x63, 0x6f, 0x6d, 0x70, 0x61, 0x74, 0x69, 0x62, 0x6c, 0x65, 0x3b, 0x20, 0x46, 0x4d, 0x53, 0x63, 0x2f, 0x31, 0x2e, 0x30, 0x29, 0x00, 0x06, 0x73, 0x77, 0x66, 0x55, 0x72, 0x6c, 0x02, 0x00, 0x16, 0x72, 0x74, 0x6d, 0x70, 0x3a, 0x2f, 0x2f, 0x31, 0x36, 0x39, 0x2e, 0x35, 0x35, 0x2e, 0x38, 0x2e, 0x34, 0x2f, 0x6c, 0x69, 0x76, 0x65, 0x00, 0x05, 0x74, 0x63, 0x55, 0x72, 0x6c, 0x02, 0x00, 0x16, 0x72, 0x74, 0x6d, 0x70, 0x3a, 0x2f, 0x2f, 0x31, 0x36, 0x39, 0x2e, 0x35, 0x35, 0x2e, 0x38, 0x2e, 0x34, 0x2f, 0x6c, 0x69, 0x76, 0x65, 0x00, 0x00, 0x09>>
    
    expected = [%RtmpCommon.Amf0.Object{
      type: :object,
      value: %{
        "app" => %RtmpCommon.Amf0.Object{type: :string, value: "live"},
        "type" => %RtmpCommon.Amf0.Object{type: :string, value: "nonprivate"},
        "flashVer" => %RtmpCommon.Amf0.Object{type: :string, value: "FMLE/3.0 (compatible; FMSc/1.0)"},
        "swfUrl" => %RtmpCommon.Amf0.Object{type: :string, value: "rtmp://169.55.8.4/live"},
        "tcUrl" => %RtmpCommon.Amf0.Object{type: :string, value: "rtmp://169.55.8.4/live"}
      }
    }]
    
    assert expected == RtmpCommon.Amf0.deserialize(binary)
  end
  
  test "Can serialize then deserialize complex object (rtmp connect)" do
    object = %RtmpCommon.Amf0.Object{
      type: :object,
      value: %{
        "app" => %RtmpCommon.Amf0.Object{type: :string, value: "live"},
        "type" => %RtmpCommon.Amf0.Object{type: :string, value: "nonprivate"},
        "flashVer" => %RtmpCommon.Amf0.Object{type: :string, value: "FMLE/3.0 (compatible; FMSc/1.0)"},
        "swfUrl" => %RtmpCommon.Amf0.Object{type: :string, value: "rtmp://169.55.8.4/live"},
        "tcUrl" => %RtmpCommon.Amf0.Object{type: :string, value: "rtmp://169.55.8.4/live"}
      }
    }
    
    result = RtmpCommon.Amf0.serialize(object)
      |> RtmpCommon.Amf0.deserialize
    
    assert [object] == result
  end
end