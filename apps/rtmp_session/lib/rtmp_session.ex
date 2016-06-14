defmodule RtmpSession do
  @moduledoc """
  Tracks a singe RTMP session, representing a single peer (server or client) at 
  one end of an RTMP conversation.

  The API allows passing in raw RTMP data packets for processing which
  can generate events the caller can choose to handle.  It also provides
  functions to generate RTMP packets to send out to the other end of the conversation.

  It is assumed that the RTMP handshake client has already been processed, that 
  the created `RtmpSession` will be processing every RTMP packet sent by its
  peer, and that the first bytes sent to the `RtmpSession` instance is the 
  first post-handshake bytes sent by the peer (so important data like the peer'send
  maximum chunk size are not missed). 
  """

  defmodule State do
    defstruct self_epoch: nil,
              peer_initial_time: nil,
              previously_received_chunk_headers: %{},
              previously_sent_chunk_headers: %{},
              bytes_waiting_to_be_sent: <<>>,
              queued_events: []
  end

  @spec new(pos_integer()) :: %State{}
  def new(peer_initial_time) do
    %State{
      peer_initial_time: peer_initial_time,
      self_epoch: :erlang.system_time(:milli_seconds)
    }
  end

  @spec process_bytes(%State{}, <<>>) :: %State{}
  def process_bytes(state = %State{}, binary) when is_binary(binary) do
    raise("not implemented")
  end

  @spec get_queued_results(%State{}) :: {%State{}, %RtmpSession.Results.QueuedData{}}
  def get_queued_results(state = %State{}) do
    bytes_to_send = state.bytes_waiting_to_be_sent
    queued_events = Enum.reverse(state.queued_events)
    new_state = %{state | bytes_waiting_to_be_sent: <<>>, queued_events: []}

    {new_state, %RtmpSession.Results.QueuedData{
      bytes_to_send: bytes_to_send,
      queued_events: queued_events
    }}
  end
end
