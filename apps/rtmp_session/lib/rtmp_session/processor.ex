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

  defmodule State do
    defstruct current_stage: :started
  end

  @spec new() :: %State{}
  def new() do
    %State{}
  end

  @type handle_result :: {:response, %RtmpMessage{}} | {:event, RtmpEvents.t} 

  @spec handle(%State{}, %RtmpMessage{}) :: {%State{}, [handle_result]}
  def handle(state = %State{}, message = %RtmpMessage{}) do
    case RtmpMessage.unpack(message) do
      {:ok, unpacked_message} -> do_handle(state, message, unpacked_message)
      {:error, :unknown_message_type} -> 
        _ = Logger.info "No known way to unpack message type #{message.message_type_id}"  
    end
  end

  defp do_handle(state, _raw_message, %RtmpMessages.SetChunkSize{size: size}) do
    {state, [{:event, %RtmpEvents.PeerChunkSizeChanged{new_chunk_size: size}}]}
  end

  defp do_handle(state, message, %{__struct__: message_type}) do
    simple_name = String.replace(to_string(message_type), "Elixir.RtmpSession.Messages.", "")

    _ = Logger.info "Unable to handle #{simple_name} message on stream id #{message.stream_id}"
    {state, []}
  end
end