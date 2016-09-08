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
    {state, [{:unhandleable, message}]}
  end
end