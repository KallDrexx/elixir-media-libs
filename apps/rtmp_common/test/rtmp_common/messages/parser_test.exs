defmodule RtmpCommon.Messages.ParserTest do
  use ExUnit.Case, async: true
  
  test "Can Parse SetChunkSize message" do
    {:ok, message} = RtmpCommon.Messages.Parser.parse(1, <<4000::32>>)
    
    %RtmpCommon.Messages.Types.SetChunkSize{size: 4000} = message
  end
  
  test "Can parse Abort message" do
    {:ok, message} = RtmpCommon.Messages.Parser.parse(2, <<500::32>>)
    
    %RtmpCommon.Messages.Types.Abort{stream_id: 500} = message
  end
  
  test "Can parse Acknowledgement message" do
    {:ok, message} = RtmpCommon.Messages.Parser.parse(3, <<25::32>>)
    
    %RtmpCommon.Messages.Types.Acknowledgement{sequence_number: 25} = message
  end
  
  test "Can parse Window Acknowlegement Size message" do
    {:ok, message} = RtmpCommon.Messages.Parser.parse(5, <<26::32>>)
    
    %RtmpCommon.Messages.Types.WindowAcknowledgementSize{size: 26} = message
  end
  
  test "Can parse Set Peer Bandwidth message" do
    {:ok, message} = RtmpCommon.Messages.Parser.parse(6, <<20::32, 1::8>>)
    
    %RtmpCommon.Messages.Types.SetPeerBandwidth{window_size: 20, limit_type: :soft} = message
  end
  
end