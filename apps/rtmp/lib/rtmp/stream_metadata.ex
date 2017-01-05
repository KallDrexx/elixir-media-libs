defmodule Rtmp.StreamMetadata do
  @type t :: %__MODULE__{
    video_width: nil | pos_integer(),
    video_height: nil | pos_integer(),
    video_codec: nil | String.t,
    video_frame_rate: nil | float(),
    video_bitrate_kbps: nil | pos_integer(),
    audio_codec: nil | String.t,
    audio_bitrate_kbps: nil | pos_integer(),
    audio_sample_rate: nil | pos_integer(),
    audio_channels: nil | pos_integer(),
    audio_is_stereo: nil | boolean(),
    encoder: nil | String.t
  }

  defstruct video_width: nil,
            video_height: nil,
            video_codec: nil,
            video_frame_rate: nil,
            video_bitrate_kbps: nil,
            audio_codec: nil,
            audio_bitrate_kbps: nil,
            audio_sample_rate: nil,
            audio_channels: nil,
            audio_is_stereo: nil,
            encoder: nil
  
end