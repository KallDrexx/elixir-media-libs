defmodule RtmpSession.ChunkIo do
  @moduledoc """
  This module provider an API for processing the raw binary that makes up
  RTMP chunks (and unpacking the enclosed RTMP message within) and allows
  serializing RTMP messages into binary RTMP chunks  
  """

  defmodule State do
    defstruct peer_max_chunk_size: 128,
              received_headers: %{},
              in_progress_chunk: nil,
              unparsed_binary: <<>>
  end

  @spec new() :: %State{}
  def new() do
    %State{}
  end

  @spec deserialize(%State{}, <<>>) :: {%State{}, :incomplete} | {%State{}, %RtmpSession.Messages.RtmpMessage{}} 
  def deserialize(_state = %State{}, binary) when is_binary(binary) do
    raise("not implemented")
  end

  @spec serialize(%State{}, %RtmpSession.Messages.RtmpMessage{}) :: {%State{}, <<>>}
  def serialize(_state = %State{}, _message = %RtmpSession.Messages.RtmpMessage{}) do
    raise("not implemented")
  end

end