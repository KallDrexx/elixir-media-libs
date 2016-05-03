defmodule RtmpCommon.Messages.Message do
  @callback parse(binary) :: any
  @callback to_response(struct()) :: {:ok, %RtmpCommon.Messages.Response{}}
end