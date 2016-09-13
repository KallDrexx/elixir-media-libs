defmodule RtmpSession.ProcessorTest do
  use ExUnit.Case, async: true
  use ListAssertions

  alias RtmpSession.RtmpMessage, as: RtmpMessage
  alias RtmpSession.Processor, as: RtmpProcessor
  alias RtmpSession.Events, as: Events

  setup do
    processor = RtmpProcessor.new()
    {:ok, processor: processor} 
  end

  test "Can handle peer chunk size message", %{processor: processor} do
    alias RtmpSession.Messages.SetChunkSize, as: SetChunkSize

    {:ok, message} = SetChunkSize.serialize(%SetChunkSize{size: 4096})
    {_, results} = RtmpProcessor.handle(processor, message)

    assert_list_contains(results, {:event, %Events.PeerChunkSizeChanged{new_chunk_size: 4096}})
  end
end