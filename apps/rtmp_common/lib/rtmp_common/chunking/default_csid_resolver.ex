defmodule RtmpCommon.Chunking.DefaultCsidResolver do
  @moduledoc """
  Naive strategy for resolving RTMP chunk stream ids, using the
  message behaviour callbacks to retrieve the default csid
  for the message intending to be sent
  
  """
  
  def get_csid(message = %{__struct__: struct_type}) do
    struct_type.get_default_chunk_stream_id(message)
  end
end