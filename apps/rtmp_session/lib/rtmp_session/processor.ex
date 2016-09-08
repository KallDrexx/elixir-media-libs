defmodule RtmpSession.Processor do
  @moduledoc """
  The RTMP session processor represents the core finite state machine dictating
  how incoming RTMP messages should be handled, including determining what RTMP messages
  should be sent to the peer and what events the session needs to react to.
  """

  alias RtmpSession.RtmpMessage, as: RtmpMessage
  alias RtmpSession.Events, as: RtmpEvents

  defmodule State do
    defstruct current_stage: :started
  end

  @spec new() :: %State{}
  def new() do
    %State{}
  end

  @type handle_result :: {:response, %RtmpMessage{}} |
    {:event, RtmpEvents.t} |
    {:unhandleable, %RtmpMessage{}}

  @spec handle(%State{}, %RtmpMessage{}) :: {%State{}, [handle_result]}
  def handle(state = %State{}, message = %RtmpMessage{}) do
    {:ok, unpacked_message} = RtmpMessage.unpack(message)
    do_handle(state, message, unpacked_message)
  end

  defp do_handle(state, _raw_message, %RtmpSession.Messages.SetChunkSize{size: size}) do
    {state, [{:event, %RtmpEvents.PeerChunkSizeChanged{new_chunk_size: size}}]}
  end

  defp do_handle(state, message, _) do
    {state, [{:unhandleable, message}]}
  end
end