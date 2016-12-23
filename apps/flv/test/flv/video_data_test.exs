defmodule Flv.VideoDataTest do
  use ExUnit.Case, async: true

  test "Can parse avc keyframe with sequence header packet type" do
    binary = Base.decode16!("17000000000164001FFFE1001B6764001FACD9405005BA6A021A0280000003008000001E478C18CB01000468EFBCB0")
    expected_data = Base.decode16!("0000000164001FFFE1001B6764001FACD9405005BA6A021A0280000003008000001E478C18CB01000468EFBCB0")

    assert {:ok, %Flv.VideoData{
      frame_type: :keyframe,
      codec_id: :avc,
      avc_packet_type: :sequence_header,
      composition_time: 0,
      data: ^expected_data
    }} = Flv.VideoData.parse(binary)
  end

  test "Can parse avc keyframe with nalu packet type" do
    binary = Base.decode16!("1701000042000002F30605FFFFEFDC45E9BDE6D948B7962CD820D923EEEF78323634202D20636F7265203134362072323533382031323133393663202D20482E3236342F4D5045472D342041564320636F646563202D20436F70796C6566742032303033")
    expected_data = Base.decode16!("000002F30605FFFFEFDC45E9BDE6D948B7962CD820D923EEEF78323634202D20636F7265203134362072323533382031323133393663202D20482E3236342F4D5045472D342041564320636F646563202D20436F70796C6566742032303033")

    assert {:ok, %Flv.VideoData{
      frame_type: :keyframe,
      codec_id: :avc,
      avc_packet_type: :nalu,
      composition_time: 66,
      data: ^expected_data
    }} = Flv.VideoData.parse(binary)
  end

  test "Can parse avc interframe with nalu packet type" do
    binary = Base.decode16!("270100004300000366419A211888FFDAC9C56643D3F25D669E7653")
    expected_data = Base.decode16!("00000366419A211888FFDAC9C56643D3F25D669E7653")

    assert {:ok, %Flv.VideoData{
      frame_type: :interframe,
      codec_id: :avc,
      avc_packet_type: :nalu,
      composition_time: 67,
      data: ^expected_data
    }} = Flv.VideoData.parse(binary)
  end

  test "Error when invalid video packet" do
    binary = Base.decode16!("FF4300000366419A211888FFDAC9C56643D3F25D669E")

    assert :error = Flv.VideoData.parse(binary)
  end
end