defmodule SimpleRtmpServer.Worker do
  alias RtmpSession.Events, as: RtmpEvents
  require Logger

  @behaviour GenRtmpServer

  defmodule State do
    defstruct session_id: nil,
              client_ip: nil
  end

  def start_link() do
    options = %GenRtmpServer.RtmpOptions{}
    GenRtmpServer.start_link(__MODULE__, options)
  end

  def init(session_id, client_ip) do
    _ = Logger.info "#{session_id}: simple rtmp server session started"

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

  def play_requested(%RtmpEvents.PlayStreamRequested{}, state = %State{}) do
    {:accepted, state}
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
end