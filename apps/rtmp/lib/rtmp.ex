defmodule Rtmp do

  @type connection_id :: String.t
  @type system_time_ms :: integer
  @type app_name :: String.t
  @type stream_key :: String.t

  @type deserialized_message :: Rtmp.Protocol.Messages.VideoData.t |
                                Rtmp.Protocol.Messages.AudioData.t |
                                Rtmp.Protocol.Messages.Abort.t |
                                Rtmp.Protocol.Messages.Acknowledgement.t |
                                Rtmp.Protocol.Messages.Amf0Command.t |
                                Rtmp.Protocol.Messages.Amf0Data.t |
                                Rtmp.Protocol.Messages.SetChunkSize.t |
                                Rtmp.Protocol.Messages.SetPeerBandwidth.t |
                                Rtmp.Protocol.Messages.UserControl.t |
                                Rtmp.Protocol.Messages.WindowAcknowledgementSize.t
  
end