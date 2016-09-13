defmodule RtmpSession.Processor do
  @moduledoc """
  The RTMP session processor represents the core finite state machine dictating
  how incoming RTMP messages should be handled, including determining what RTMP messages
  should be sent to the peer and what events the session needs to react to.
  """

  alias RtmpSession.RtmpMessage, as: RtmpMessage
  alias RtmpSession.Messages, as: RtmpMessages
  alias RtmpSession.Events, as: RtmpEvents

  require Logger

  @type handle_result :: {:response, %RtmpMessage{}} | {:event, RtmpEvents.t}

  defmodule State do
    defstruct current_stage: :started,
      peer_window_ack_size: nil,
      peer_bytes_received: 0,
      last_acknowledgement_sent_at: 0 
  end

  @spec new() :: %State{}
  def new() do
    %State{}
  end

  @spec handle(%State{}, %RtmpMessage{}, non_neg_integer()) :: {%State{}, [handle_result]}
  def handle(state = %State{}, message = %RtmpMessage{}, bytes_received) do
    state = %{state | peer_bytes_received: state.peer_bytes_received + bytes_received}

    bytes_since_last_ack = state.peer_bytes_received - state.last_acknowledgement_sent_at
    {state, initial_results} = cond do
      state.peer_window_ack_size == nil ->
        {state, []}

      bytes_since_last_ack < state.peer_window_ack_size ->
        {state, []}

      true ->
        state = %{state | last_acknowledgement_sent_at: state.peer_bytes_received }
        ack_message = %RtmpMessages.Acknowledgement{sequence_number: state.peer_bytes_received}
        results = [{:response, serialize_message(state, ack_message, 0)}]
        {state, results}
    end    

    case RtmpMessage.unpack(message) do
      {:ok, unpacked_message} -> do_handle(state, message, unpacked_message, initial_results)
      {:error, :unknown_message_type} -> 
        _ = Logger.info "No known way to unpack message type #{message.message_type_id}"  
    end
  end

  defp do_handle(state, _raw_message, %RtmpMessages.SetChunkSize{size: size}, results_so_far) do
    {state, [{:event, %RtmpEvents.PeerChunkSizeChanged{new_chunk_size: size}} | results_so_far]}
  end

  defp do_handle(state, _raw_message, %RtmpMessages.WindowAcknowledgementSize{size: size}, results_so_far) do
    state = %{state | peer_window_ack_size: size}
    {state, results_so_far}
  end

  defp do_handle(state, message, %{__struct__: message_type}, results_so_far) do
    simple_name = String.replace(to_string(message_type), "Elixir.RtmpSession.Messages.", "")

    _ = Logger.info "Unable to handle #{simple_name} message on stream id #{message.stream_id}"
    {state, results_so_far}
  end
  
  defp serialize_message(state, message, stream_id) do
    %{__struct__: type} = message
    {:ok, result} = type.serialize(message)
    %{result | stream_id: stream_id}
  end
end