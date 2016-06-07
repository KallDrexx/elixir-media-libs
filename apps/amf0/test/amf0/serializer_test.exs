defmodule Amf0.SerializerTest do
  use ExUnit.Case, async: true

  test "Can serialize number" do    
    assert <<0::8, 332::float-64>> = Amf0.serialize(332)
  end

  test "Can serialize true boolean" do
    assert <<1::8, 1::8>> = Amf0.serialize(true)
  end
  
  test "Can serialize UTF8-1 string" do
    assert (<<2::8, 4::16>> <> "test") = Amf0.serialize("test")
  end
  
  test "Can serialize null value" do
    assert <<5::8>> = Amf0.serialize(nil)
  end
  
  test "Can serialize object" do
    assert (<<3::8, 4::16>> <> "test" <> <<2::8, 5::16>> <> "value" <> <<0, 0, 9>>) 
      = Amf0.serialize(%{"test" => "value"})
  end
  
  test "Can serialize multiple values" do
    assert (<<0::8, 532::float-64, 1::8, 1::8>>) = Amf0.serialize([532, true])
  end
  
  test "Can serialize then deserialize complex object (rtmp connect)" do
    # Since we can't predict map ordering, we can't guarantee order of binary,
    #   so just make sure that the complex object can be serialized then deserialized
    #   back again.

    object = %{
      "app" => "live",
      "type" => "nonprivate",
      "flashVer" => "FMLE/3.0 (compatible; FMSc/1.0)",
      "swfUrl" => "rtmp://169.55.8.4/live",
      "tcUrl" => "rtmp://169.55.8.4/live"
    }

    {:ok, [result]} =
      Amf0.serialize(object)
      |> Amf0.deserialize() 
    
    assert object == result
  end
end