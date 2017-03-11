defmodule SimpleRtmpProxy.Worker do
  @moduledoc """
  Simple implementation of a RTMP server that relays video to another
  RTMP server.

  RTMP playback clients will be disconnected
  """

  alias Rtmp.ServerSession.Events, as: RtmpEvents
  require Logger

  @behaviour GenRtmpServer

  defmodule State do
    @moduledoc false

    defstruct session_id: nil,
              client_ip: nil
  end

  def start_link() do
    options = %GenRtmpServer.RtmpOptions{log_mode: :none}
    GenRtmpServer.start_link(__MODULE__, options)
  end

  def init(session_id, client_ip) do
    _ = Logger.info "#{session_id}: simple rtmp proxy session started"

    state = %State{
      session_id: session_id,
      client_ip: client_ip
    }

    {:ok, state}
  end

  def connection_requested(%RtmpEvents.ConnectionRequested{}, state = %State{}) do
    {:accepted, state}
  end

  def publish_requested(%RtmpEvents.PublishStreamRequested{}, state = %State{}) do
    {:accepted, state}
  end

  def publish_finished(%RtmpEvents.PublishingFinished{}, state = %State{}) do
    {:ok, state}
  end

  def play_requested(%RtmpEvents.PlayStreamRequested{}, state = %State{}) do
    {{:rejected, :disconnect, "No playback allowed"}, state}
  end

  def play_finished(%RtmpEvents.PlayStreamFinished{}, state = %State{}) do
    {:ok, state}
  end

  def metadata_received(%RtmpEvents.StreamMetaDataChanged{}, state = %State{}) do
    {:ok, state}
  end

  def audio_video_data_received(%RtmpEvents.AudioVideoDataReceived{}, state = %State{}) do
    {:ok, state}
  end

  def byte_io_totals_updated(%RtmpEvents.NewByteIOTotals{}, state = %State{}) do
    {:ok, state}
  end

  def acknowledgement_received(%RtmpEvents.AcknowledgementReceived{}, state = %State{}) do
    {:ok, state}
  end

  def ping_request_sent(%RtmpEvents.PingRequestSent{}, state = %State{}) do
    {:ok, state}
  end

  def ping_response_received(%RtmpEvents.PingResponseReceived{}, state = %State{}) do
    {:ok, state}
  end

  def code_change(_, state = %State{}) do
    {:ok, state}
  end

  def handle_message(message, state = %State{}) do
    _ = Logger.debug("#{state.session_id}: Unknown message received: #{inspect(message)}")
    {:ok, state}
  end

end