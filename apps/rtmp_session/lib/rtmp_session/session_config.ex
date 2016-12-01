defmodule RtmpSession.SessionConfig do
  @moduledoc """
  Represents configuration options that governs how an RTMP session should operate
  """

  @type t :: %__MODULE__{
    fms_version: String.t,
    chunk_size: pos_integer(),
    window_ack_size: pos_integer(),
    peer_bandwidth: pos_integer(),
    io_log_mode: :none | :raw_io
  }

  defstruct fms_version: "FMS/3,0,0,123",
    chunk_size: 4096,
    peer_bandwidth: 2500000,
    window_ack_size: 1048576,
    io_log_mode: :none
end