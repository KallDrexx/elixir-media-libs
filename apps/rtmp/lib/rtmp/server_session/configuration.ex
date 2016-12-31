defmodule Rtmp.ServerSession.Configuration do
  @moduledoc """
  Represents configuration options that governs how an RTMP server session should operate
  """

  @type t :: %__MODULE__{
    fms_version: String.t,
    chunk_size: pos_integer(),
    window_ack_size: pos_integer(),
    peer_bandwidth: pos_integer(),
    io_log_mode: :none | :raw_io
  }

  defstruct fms_version: "FMS/3,0,1,123",
    chunk_size: 4096,
    peer_bandwidth: 2500000,
    window_ack_size: 1073741824,
    io_log_mode: :none
end