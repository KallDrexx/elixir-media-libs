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

  test "Can handle peer window ack size and sends acknowledgement when received enough bytes", %{processor: processor} do
    alias RtmpSession.Messages.WindowAcknowledgementSize, as: WindowAcknowledgementSize
    alias RtmpSession.Messages.Acknowledgement, as: Acknowledgement

    {:ok, message} = WindowAcknowledgementSize.serialize(%WindowAcknowledgementSize{size: 500})
    {processor, results1} = RtmpProcessor.handle(processor, message)
    {_, results2} = RtmpProcessor.notify_bytes_received(processor, 800)

    {:ok, %RtmpMessage {
      message_type_id: expected_message_type_id,
      payload: expected_payload,
    }} = Acknowledgement.serialize(%Acknowledgement{sequence_number: 800})

    assert(results1 = [])
    assert_list_contains(results2, {:response, %RtmpMessage{
      message_type_id: ^expected_message_type_id,
      payload: ^expected_payload
    }})
  end
end