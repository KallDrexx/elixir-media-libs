defmodule RtmpSession do
  @moduledoc """
  Tracks a singe RTMP session, representing a single peer (server or client) at 
  one end of an RTMP conversation.

  The API allows passing in raw RTMP data packets for processing which
  can generate events the caller can choose to handle.

  It is assumed that the RTMP handshake client has already been processed, that 
  the created `RtmpSession` will be processing every RTMP packet sent by its
  peer, and that the first bytes sent to the `RtmpSession` instance is the 
  first post-handshake bytes sent by the peer (so important data like the peer'send
  maximum chunk size are not missed). 
  """

  alias RtmpSession.ChunkIo, as: ChunkIo
  alias RtmpSession.SessionResults, as: SessionResults
  alias RtmpSession.RtmpMessage, as: RtmpMessage
  alias RtmpSession.Processor, as: Processor

  require Logger

  defmodule State do
    defstruct self_epoch: nil,
              peer_initial_time: nil,
              chunk_io: nil,
              processor: nil
  end

  @spec new(pos_integer()) :: %State{}
  def new(peer_initial_time) do
    %State{
      peer_initial_time: peer_initial_time,
      self_epoch: :erlang.system_time(:milli_seconds),
      chunk_io: ChunkIo.new(),
      processor: Processor.new()
    }
  end

  @spec process_bytes(%State{}, <<>>) :: {%State{}, %RtmpSession.SessionResults{}}
  def process_bytes(state = %State{}, binary) when is_binary(binary) do
    {state, results} = do_process_bytes(state, binary, %SessionResults{})
    results = %{results | events: Enum.reverse(results.events)}

    {state, results}
  end

  defp do_process_bytes(state, binary, results_so_far) do
    {chunk_io, chunk_result} = ChunkIo.deserialize(state.chunk_io, binary)
    state = %{state | chunk_io: chunk_io}

    case chunk_result do
      :incomplete -> {state, results_so_far}
      :split_message -> do_process_bytes(state, <<>>, results_so_far)
      message = %RtmpMessage{} -> act_on_message(state, message, results_so_far)
    end
  end

  defp act_on_message(state, message, results_so_far) do
    {processor, processor_results} = Processor.handle(state.processor, message)
    state = %{state | processor: processor}
  
    handle_proc_result(state, results_so_far, processor_results)
  end

  defp handle_proc_result(state, results_so_far, []) do
    {state, results_so_far}
  end

  defp handle_proc_result(state, results_so_far, [proc_result_head | proc_result_tail]) do
    case proc_result_head do
      {:response, message = %RtmpMessage{}} -> 
        {chunk_io, data} = ChunkIo.serialize(state.chunk_io, message, 0, false)
        state = %{state | chunk_io: chunk_io}
        results_so_far = %{results_so_far | bytes_to_send: [results_so_far.bytes_to_send | data] }
        handle_proc_result(state, results_so_far, proc_result_tail)

      {:event, event} ->
        results_so_far = %{results_so_far | events: [event | results_so_far.events]}
        handle_proc_result(state, results_so_far, proc_result_tail)

      {:unhandleable, message = %RtmpMessage{}} ->
        _ = Logger.info "Unable to handle message type #{message.message_type_id} on stream id #{message.stream_id}"
        handle_proc_result(state, results_so_far, proc_result_tail)
    end
  end
end
