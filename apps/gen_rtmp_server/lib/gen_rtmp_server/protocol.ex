defmodule GenRtmpServer.Protocol do
  @moduledoc """
  Ranch protocol that abstracts the RTMP protocol logic away
  """

  @behaviour :ranch_protocol
  @behaviour Rtmp.Behaviours.EventReceiver

  alias Rtmp.ServerSession.Events, as: RtmpEvents
  alias Rtmp.Protocol.Messages, as: RtmpMessages

  use GenServer
  require Logger

  defmodule State do
    defstruct socket: nil,
              transport: nil,
              session_id: nil,
              bytes_read: 0,
              bytes_sent: 0,
              handshake_completed: false,
              handshake_instance: nil,
              protocol_handler_pid: nil,
              session_handler_pid: nil,
              gen_rtmp_server_adopter: nil,
              adopter_state: nil,
              session_config: nil,
              log_files: %{},
              adopter_args: nil
  end

  @doc "Starts the protocol for the accepted socket"
  def start_link(ref, socket, transport, [module, options = %GenRtmpServer.RtmpOptions{}, adopter_args]) do
    :proc_lib.start_link(__MODULE__, :init, [ref, socket, transport, module, options, adopter_args])
  end

  def send_event(pid, event) do
    GenServer.cast(pid, {:session_event, event})
  end

  def send_data(pid, binary) do
    GenServer.cast(pid, {:rtmp_output, binary})
  end

  def init(ref, socket, transport, module, options, adopter_args) do
    :ok = :proc_lib.init_ack({:ok, self()})
    :ok = :ranch.accept_ack(ref)

    session_id = UUID.uuid4()
    client_ip_string = get_ip_address(socket)

    _ = Logger.info "#{session_id}: client connected from ip #{client_ip_string}"

    {handshake_instance, %Rtmp.Handshake.ParseResult{bytes_to_send: bytes_to_send}}
      = Rtmp.Handshake.new(:unknown) # Let the client's handshake tell us the format

    :ok = transport.send(socket, bytes_to_send)

    options_list = GenRtmpServer.RtmpOptions.to_keyword_list(options)
    session_config = create_session_config(options_list)

    state = %State{
      socket: socket,
      transport: transport,
      handshake_instance: handshake_instance,
      session_id: session_id,
      gen_rtmp_server_adopter: module,
      session_config: session_config,
      adopter_args: adopter_args,
    }

    set_socket_options(state)
    :gen_server.enter_loop(__MODULE__, [], state)
  end

  def handle_cast({:session_event, event}, state) do
    state = handle_event(event, state)
    {:noreply, state}
  end

  def handle_cast({:rtmp_output, binary}, state) do
    state.transport.send(state.socket, binary)
    log_io_data(state, :output, binary)
    {:noreply, state}
  end

  def handle_info({:tcp, _, binary}, state = %State{handshake_completed: false}) do
    case Rtmp.Handshake.process_bytes(state.handshake_instance, binary) do
      {instance, result = %Rtmp.Handshake.ParseResult{current_state: :waiting_for_data}} ->
        if byte_size(result.bytes_to_send) > 0, do: state.transport.send(state.socket, result.bytes_to_send)

        new_state = %{state | handshake_instance: instance}
        set_socket_options(new_state)
        {:noreply, new_state}
      
      {instance, result = %Rtmp.Handshake.ParseResult{current_state: :success}} ->
        if byte_size(result.bytes_to_send) > 0, do: state.transport.send(state.socket, result.bytes_to_send)

        {_, %Rtmp.Handshake.HandshakeResult{remaining_binary: remaining_binary}}
          = Rtmp.Handshake.get_handshake_result(instance)

        {:ok, protocol_pid} = Rtmp.Protocol.Handler.start_link(state.session_id, self(), __MODULE__)
        {:ok, session_pid} = Rtmp.ServerSession.Handler.start_link(state.session_id, state.session_config)

        :ok = Rtmp.Protocol.Handler.set_session(protocol_pid, session_pid, Rtmp.ServerSession.Handler)
        :ok = Rtmp.ServerSession.Handler.set_rtmp_output_handler(session_pid, protocol_pid, Rtmp.Protocol.Handler)
        :ok = Rtmp.ServerSession.Handler.set_event_handler(session_pid, self(), __MODULE__)

        {:ok, adopter_state} = state.gen_rtmp_server_adopter.init(state.session_id, get_ip_address(state.socket), state.adopter_args)
        :ok = Rtmp.Protocol.Handler.notify_input(protocol_pid, remaining_binary)
        :ok = Rtmp.ServerSession.Handler.send_stream_zero_begin(session_pid)

        state = %{state |
          handshake_instance: nil,
          handshake_completed: true,
          protocol_handler_pid: protocol_pid,
          session_handler_pid: session_pid,
          adopter_state: adopter_state
        }

        state = prepare_log_files(state)

        set_socket_options(state)
        {:noreply, state}

      {_, %Rtmp.Handshake.ParseResult{current_state: :failure}} ->
        _ = Logger.info "#{state.session_id}: Client failed the handshake, disconnecting..."

        state.transport.close(state.socket)
        {:noreply, state}
    end    
  end

  def handle_info({:tcp, _, binary}, state = %State{}) do
    log_io_data(state, :input, binary)

    :ok = Rtmp.Protocol.Handler.notify_input(state.protocol_handler_pid, binary)
    set_socket_options(state)
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _}, state = %State{}) do
    _ = Logger.info "#{state.session_id}: socket closed" 
    {:stop, :normal, state}
  end

  def handle_info({:rtmp_send, data, send_to_stream_id, forced_timestamp}, state = %State{}) do
    rtmp_send(data, send_to_stream_id, state, forced_timestamp)
    {:noreply, state}
  end

  def handle_info(:send_ping_request, state = %State{}) do
    :ok = Rtmp.ServerSession.Handler.send_ping_request(state.session_handler_pid)
    {:noreply, state}
  end
  
  def handle_info(message, state = %State{}) do
    {:ok, adopter_state} = state.gen_rtmp_server_adopter.handle_message(message, state.adopter_state)
    state = %{state | adopter_state: adopter_state}

    set_socket_options(state) # Just in case
    {:noreply, state}
  end

  def code_change(old_version, state, _) do
    case state.gen_rtmp_server_adopter.code_change(old_version, state.adopter_state) do
      {:ok, new_adopter_state} ->
        state = %{state | adopter_state: new_adopter_state}
        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp set_socket_options(state = %State{}) do
    # Ignore the result, as theoretically a tcp closed message should be arriving
    # that will kill this connection
    _ = state.transport.setopts(state.socket, active: :once, packet: :raw, buffer: 4096)
  end

  defp create_session_config(options) do
    config = %Rtmp.ServerSession.Configuration{}
    config = case Keyword.fetch(options, :fms_version) do
      {:ok, value} -> %{config| fms_version: value}
      :error -> config
    end

    config = case Keyword.fetch(options, :chunk_size) do
      {:ok, value} -> %{config| chunk_size: value}
      :error -> config
    end

    config = case Keyword.fetch(options, :log_mode) do
      {:ok, value} -> %{config| io_log_mode: value}
      :error -> config
    end

    config
  end

  defp get_ip_address(socket) do
    {:ok, {ip, _port}} = :inet.peername(socket)
    ip |> Tuple.to_list() |> Enum.join(".")
  end

  defp handle_event(event = %RtmpEvents.ConnectionRequested{}, state) do
    case state.gen_rtmp_server_adopter.connection_requested(event, state.adopter_state) do
      {:accepted, adopter_state} -> 
        _ = Logger.info("#{state.session_id}: Connection request accepted (app: '#{event.app_name}')")
        handle_accepted_request(state, event.request_id, adopter_state)

      {{:rejected, command, reason}, adopter_state} ->
        _ = Logger.info("#{state.session_id}: Connection request rejected (app: '#{event.app_name}') - #{reason}")
        handle_rejected_request(command, state, event.request_id, adopter_state)
    end
  end

  defp handle_event(event = %RtmpEvents.PublishStreamRequested{}, state) do
    case state.gen_rtmp_server_adopter.publish_requested(event, state.adopter_state) do
      {:accepted, adopter_state} ->
        _ = Logger.info("#{state.session_id}: Publish stream request accepted (app: '#{event.app_name}', key: '#{event.stream_key}')")
        handle_accepted_request(state, event.request_id, adopter_state)

      {{:rejected, command, reason}, adopter_state} ->
        _ = Logger.info("#{state.session_id}: Publish stream request rejected (app: '#{event.app_name}', key: '#{event.stream_key}') - #{reason}")

        handle_rejected_request(command, state, event.request_id, adopter_state)
    end
  end

  defp handle_event(event = %RtmpEvents.PublishingFinished{}, state) do
    {:ok, adopter_state} = state.gen_rtmp_server_adopter.publish_finished(event, state.adopter_state)
    %{state | adopter_state: adopter_state}
  end

  defp handle_event(%RtmpEvents.PeerChunkSizeChanged{}, state) do
    state
  end

  defp handle_event(event = %RtmpEvents.AudioVideoDataReceived{}, state) do
    {:ok, adopter_state} = state.gen_rtmp_server_adopter.audio_video_data_received(event, state.adopter_state)
    %{state | adopter_state: adopter_state}
  end

  defp handle_event(event = %RtmpEvents.StreamMetaDataChanged{}, state) do
    {:ok, adopter_state} = state.gen_rtmp_server_adopter.metadata_received(event, state.adopter_state)
    %{state | adopter_state: adopter_state}
  end

  defp handle_event(event = %RtmpEvents.PlayStreamRequested{}, state) do
    case state.gen_rtmp_server_adopter.play_requested(event, state.adopter_state) do
      {:accepted, adopter_state} ->
        _ = Logger.info("#{state.session_id}: Play stream request accepted (app: '#{event.app_name}', key: '#{event.stream_key}')")
        handle_accepted_request(state, event.request_id, adopter_state)

      {{:rejected, command, reason}, adopter_state} ->
        _ = Logger.info("#{state.session_id}: Play stream request rejected (app: '#{event.app_name}', key: '#{event.stream_key}') - #{reason}")

        handle_rejected_request(command, state, event.request_id, adopter_state)
    end
  end

  defp handle_event(event = %RtmpEvents.PlayStreamFinished{}, state) do
    {:ok, adopter_state} = state.gen_rtmp_server_adopter.play_finished(event, state.adopter_state)
    %{state | adopter_state: adopter_state}
  end

  defp handle_event(event = %RtmpEvents.NewByteIOTotals{}, state) do
    {:ok, adopter_state} = state.gen_rtmp_server_adopter.byte_io_totals_updated(event, state.adopter_state)
    %{state | adopter_state: adopter_state}
  end

  defp handle_event(event = %RtmpEvents.AcknowledgementReceived{}, state) do
    {:ok, adopter_state} = state.gen_rtmp_server_adopter.acknowledgement_received(event, state.adopter_state)
    %{state | adopter_state: adopter_state}
  end

  defp handle_event(event = %RtmpEvents.PingRequestSent{}, state) do
    {:ok, adopter_state} = state.gen_rtmp_server_adopter.ping_request_sent(event, state.adopter_state)
    %{state | adopter_state: adopter_state}
  end

  defp handle_event(event = %RtmpEvents.PingResponseReceived{}, state) do
    {:ok, adopter_state} = state.gen_rtmp_server_adopter.ping_response_received(event, state.adopter_state)
    %{state | adopter_state: adopter_state}
  end

  defp handle_event(event, state) do
    _ = Logger.warn("#{state.session_id}: No code to handle RTMP session event of type #{inspect(event)}")
    state
  end

  defp handle_accepted_request(state, request_id, adopter_state) do
    :ok = Rtmp.ServerSession.Handler.accept_request(state.session_handler_pid, request_id)
    %{state | adopter_state: adopter_state}
  end

  defp handle_rejected_request(command, state, _request_id, new_adopter_state) do
    case command do
      :disconnect -> state.transport.close(state.socket)
      _ -> :ok
    end

    %{state | adopter_state: new_adopter_state}
  end

  defp rtmp_send(data, send_to_stream_id, state, forced_timestamp) do
    content = form_outbound_rtmp_message(data)
    :ok = Rtmp.ServerSession.Handler.send_rtmp_message(state.session_handler_pid, content, send_to_stream_id, forced_timestamp)
  end

  defp form_outbound_rtmp_message(av_data = %GenRtmpServer.AudioVideoData{}) do
    case av_data.data_type do
      :audio -> %RtmpMessages.AudioData{data: av_data.data}
      :video -> %RtmpMessages.VideoData{data: av_data.data}
    end
  end

  defp form_outbound_rtmp_message(%GenRtmpServer.MetaData{details: metadata}) do
    %RtmpMessages.Amf0Data{parameters: [
      "onMetaData",
      %{
        "width" => metadata.video_width,
        "height" => metadata.video_height,
        "framerate" => metadata.video_frame_rate,
        "videocodecid" => metadata.video_codec,
        "audiocodecid" => metadata.audio_codec,
        "audiochannels" => metadata.audio_channels,
        "audiodatarate" => metadata.audio_bitrate_kbps,
        "audiosamplerate" => metadata.audio_sample_rate,
        "videodatarate" => metadata.video_bitrate_kbps
      }
    ]}
  end

  defp form_outbound_rtmp_message(data) do
    raise("No known way to form outbound rtmp message for data: #{inspect(data)}")
  end

  defp prepare_log_files(state = %State{session_config: %Rtmp.ServerSession.Configuration{io_log_mode: :none}}) do
    state
  end

  defp prepare_log_files(state = %State{session_config: %Rtmp.ServerSession.Configuration{io_log_mode: :raw_io}}) do
    path = "dumps"

    :ok = File.mkdir_p!(path)
    input = File.open!("#{path}/#{state.session_id}.input.rtmp", [:binary, :write, :exclusive])
    output = File.open!("#{path}/#{state.session_id}.output.rtmp", [:binary, :write, :exclusive])

    log_files = Map.put(state.log_files, :input_append, input)
    log_files = Map.put(log_files, :output_append, output)
    %{state | log_files: log_files}
  end

  defp log_io_data(%State{session_config: %Rtmp.ServerSession.Configuration{io_log_mode: :none}}, _input_or_output, _data) do
    :ok
  end

  defp log_io_data(_, _, <<>>) do
    :ok
  end

  defp log_io_data(state = %State{session_config: %Rtmp.ServerSession.Configuration{io_log_mode: :raw_io}}, :input, data) do
    file = Map.fetch!(state.log_files, :input_append)
    IO.binwrite(file, data)
  end

  defp log_io_data(state = %State{session_config: %Rtmp.ServerSession.Configuration{io_log_mode: :raw_io}}, :output, data) do
    file = Map.fetch!(state.log_files, :output_append)
    IO.binwrite(file, data)
  end

end