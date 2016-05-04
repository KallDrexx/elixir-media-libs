defmodule RtmpCommon.Messages.Message do
  @callback parse(binary) :: any
  @callback serialize(struct()) :: {:ok, %RtmpCommon.Messages.SerializedMessage{}}
end