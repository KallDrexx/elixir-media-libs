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
              client_ip: nil,
              stream_key: nil,
              metadata: nil,
              video_sequence_header: nil,
              audio_sequence_header: nil,
              client_info: nil
  end

  defmodule ClientInfo do
    @moduledoc false

    defstruct host: nil,
              port: nil,
              app_name: nil
  end

  def start_link(in_port, host, out_port, app) do
    options = %GenRtmpServer.RtmpOptions{port: in_port}
    GenRtmpServer.start_link(__MODULE__, options, [host, out_port, app])
  end

  def init(session_id, client_ip, [host, port, app_name]) do
    _ = Logger.info "#{session_id}: simple rtmp proxy session started"

    state = %State{
      session_id: session_id,
      client_ip: client_ip,
      client_info: %ClientInfo{
        host: host,
        port: port,
        app_name: app_name
      }
    }

    {:ok, state}
  end

  def connection_requested(%RtmpEvents.ConnectionRequested{}, state = %State{}) do
    {:accepted, state}
  end

  def publish_requested(event = %RtmpEvents.PublishStreamRequested{}, state = %State{}) do
    case state.stream_key do
      nil ->
        state = %{state | stream_key: event.stream_key}
        {:accepted, state}

      _ ->
        {{:rejected, :ignore, "Publish already in progress on stream key #{state.stream_key}"}, state}
    end
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

  def metadata_received(event = %RtmpEvents.StreamMetaDataChanged{}, state = %State{}) do
    if event.stream_key != state.stream_key do
      message = "#{state.session_id}: Received stream metadata on stream key #{event.stream_key} but " <>
                "currently publishing on stream key #{state.stream_key}"
      raise(message)
    end

    state = %{state | metadata: event.meta_data }
    {:ok, state}
  end

  def audio_video_data_received(event = %RtmpEvents.AudioVideoDataReceived{}, state = %State{}) do
    if event.stream_key != state.stream_key do
      message = "#{state.session_id}: Received a/v data on stream key #{event.stream_key} but " <>
                "currently publishing on stream key #{state.stream_key}"
      raise(message)
    end

    state = case event.data_type do
      :audio ->
        case is_audio_sequence_header(event.data) do
          false -> state
          true -> 
            _ = Logger.debug("#{state.session_id}: Audio sequence header received")
            %{state | audio_sequence_header: event.data}
        end

      :video ->
        case is_video_sequence_header(event.data) do
          false -> state
          true -> 
            _ = Logger.debug("#{state.session_id}: Video sequence header received")
            %{state | video_sequence_header: event.data }
        end
    end 

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

  defp is_video_sequence_header(<<0x17, 0x00, _::binary>>), do: true
  defp is_video_sequence_header(_), do: false

  defp is_audio_sequence_header(<<0xaf, 0x00, _::binary>>), do: true
  defp is_audio_sequence_header(_), do: false

end