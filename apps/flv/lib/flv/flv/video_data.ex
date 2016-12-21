defmodule Flv.VideoData do
  @moduledoc "Represents a packet of video data"

  @type frametype :: :keyframe | :interframe
  @type codec_id :: :avc
  @type avc_packet_type :: :sequence_header | :nalu

  @type t :: %__MODULE__{
    frame_type: frametype,
    codec_id: codec_id,
    avc_packet_type: avc_packet_type,
    composition_time: non_neg_integer,
    data: <<>>
  }

  defstruct frame_type: nil,
            codec_id: nil,
            avc_packet_type: nil,
            composition_time: nil,
            data: <<>>
  
end