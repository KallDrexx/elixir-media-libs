defmodule Rtmp.ClientSession.Configuration do
  @type t :: %__MODULE__{
    flash_version: String.t,
    playback_buffer_length_ms: non_neg_integer
  }

  defstruct flash_version: "WIN 23,0,0,207",
            playback_buffer_length_ms: 2000
end