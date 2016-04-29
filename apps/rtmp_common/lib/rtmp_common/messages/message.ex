defmodule RtmpCommon.Messages.Message do
  @callback parse(binary) :: any 
end