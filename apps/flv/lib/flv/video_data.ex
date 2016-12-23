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


  @spec parse(<<>>) :: {:ok, __MODULE__.t} | :error
  @doc "Parses the video details from the supplied video packet"
  def parse(binary) do
    do_parse_video(binary)
  end

  defp do_parse_video(<<frame_type_id::4, 7::4, 0::8, rest::binary>>) do
    {:ok, %Flv.VideoData{
      frame_type: video_frame_type(frame_type_id),
      codec_id: :avc,
      avc_packet_type: :sequence_header,
      composition_time: 0,
      data: rest
    }}
  end

  defp do_parse_video(<<frame_type_id::4, 7::4, 1::8, time::signed-size(3)-unit(8), rest::binary>>) do
    {:ok, %Flv.VideoData{
      frame_type: video_frame_type(frame_type_id),
      codec_id: :avc,
      avc_packet_type: :nalu,
      composition_time: time,
      data: rest
    }}
  end

  defp do_parse_video(_) do
    :error
  end

  defp video_frame_type(1), do: :keyframe
  defp video_frame_type(2), do: :interframe
  defp video_frame_type(_), do: :unknown
  
end