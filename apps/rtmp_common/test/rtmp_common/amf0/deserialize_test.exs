defmodule RtmpCommon.Amf0.DeserializeTest do
  use ExUnit.Case, async: true
  
  test "Can deserialize number" do
    binary = <<0::8, 532::64>>
    expected = [%RtmpCommon.Amf0.Object{type: :number, value: 532}]
    
    assert expected == RtmpCommon.Amf0.deserialize(binary)
  end
  
  test "Can deserialize boolean" do
    binary = <<1::8, 1::8>>
    expected = [%RtmpCommon.Amf0.Object{type: :boolean, value: true}]
    
    assert expected == RtmpCommon.Amf0.deserialize(binary)
  end
  
  test "Can deserialize UTF8-1 string" do
    binary = <<2::8, 4::8>> <> "test"
    expected = [%RtmpCommon.Amf0.Object{type: :string, value: "test"}]
    
    assert expected == RtmpCommon.Amf0.deserialize(binary)
  end
end