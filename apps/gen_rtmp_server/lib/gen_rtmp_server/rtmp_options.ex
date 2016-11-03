defmodule GenRtmpServer.RtmpOptions do
  @moduledoc """
  Represents options that are available for starting an RTMP server
  """

  @type t :: %__MODULE__{
    port: pos_integer(),
    fms_version: String.t,
    chunk_size: pos_integer()
  }

  @type options_list :: [port: pos_integer, fms_version: String.t, chunk_size: pos_integer]

  defstruct port: 1935,
            fms_version: "FMS/3,0,0,1233",
            chunk_size: 4096
  
  @spec to_keyword_list(%GenRtmpServer.RtmpOptions{}) :: options_list
  def to_keyword_list(options = %GenRtmpServer.RtmpOptions{}) do
    [
      port: options.port,
      fms_version: options.fms_version,
      chunk_size: options.chunk_size
    ]
  end
end