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
  alias RtmpSession.RawMessage, as: RawMessage
  alias RtmpSession.DetailedMessage, as: DetailedMessage
  alias RtmpSession.Processor, as: Processor
  alias RtmpSession.Events, as: RtmpEvents
  alias RtmpSession.SessionConfig, as: SessionConfig

  require Logger

  @type t :: %RtmpSession.State{}
  @type app_name :: String.t
  @type stream_key :: String.t
  @type rtmp_timestamp :: non_neg_integer
  @type stream_id :: non_neg_integer
  @type forced_timestamp :: non_neg_integer | nil

  @type deserialized_message :: RtmpSession.Messages.SetChunkSize.t |
    RtmpSession.Messages.Abort.t |
    RtmpSession.Messages.Acknowledgement.t |
    RtmpSession.Messages.UserControl.t |
    RtmpSession.Messages.WindowAcknowledgementSize.t |
    RtmpSession.Messages.SetPeerBandwidth.t |
    RtmpSession.Messages.AudioData.t |
    RtmpSession.Messages.VideoData.t |
    RtmpSession.Messages.Amf0Command.t |
    RtmpSession.Messages.Amf0Data.t

  defmodule State do
    defstruct self_epoch: nil,
              peer_initial_time: nil,
              chunk_io: nil,
              processor: nil,
              session_id: nil,
              config: nil,
              log_files: %{}
  end

  @spec new(non_neg_integer(), String.t, %SessionConfig{}) :: %State{}
  def new(peer_initial_time, session_id, config \\ %SessionConfig{}) do
    state = %State{
      peer_initial_time: peer_initial_time,
      self_epoch: :erlang.system_time(:milli_seconds),
      chunk_io: ChunkIo.new(),
      processor: Processor.new(config, session_id),
      session_id: session_id,
      config: config
    }

    prepare_log_files(state)
  end

  @spec process_bytes(%State{}, <<>>) :: {%State{}, %SessionResults{}}
  def process_bytes(state = %State{}, binary) when is_binary(binary) do
    :ok = log_io_data(state, :input, binary)

    {state, results} = do_process_bytes(state, binary, %SessionResults{})
    results = %{results | events: Enum.reverse(results.events)}

    {state, results}
  end

  @spec accept_request(%State{}, non_neg_integer()) :: {%State{}, %SessionResults{}}
  def accept_request(state = %State{}, request_id) do
    {processor, results} = Processor.accept_request(state.processor, request_id)

    state = %{state | processor: processor}
    handle_proc_result(state, %SessionResults{}, results)
  end

  @spec send_rtmp_message(%State{}, stream_id, deserialized_message, forced_timestamp) :: {%State{}, %SessionResults{}}
  def send_rtmp_message(state = %State{}, stream_id, message, forced_timestamp \\ nil) do
    timestamp = case forced_timestamp do
      nil -> :os.system_time(:milli_seconds) - state.self_epoch
      x when x >= 0 -> x
    end

    detailed_message = %DetailedMessage{
      timestamp: timestamp,
      stream_id: stream_id,
      content: message
    }

    response = {:response, detailed_message}
    handle_proc_result(state, %SessionResults{}, [response])
  end

  defp do_process_bytes(state, binary, results_so_far) do
    {chunk_io, chunk_result} = ChunkIo.deserialize(state.chunk_io, binary)
    state = %{state | chunk_io: chunk_io}

    case chunk_result do
      :incomplete -> return_incomplete_result(state, results_so_far, byte_size(binary))
      :split_message -> repeat_process_bytes(state, results_so_far, byte_size(binary))
      raw_message = %RawMessage{} -> act_on_message(state, raw_message, results_so_far, byte_size(binary))
    end
  end

  defp return_incomplete_result(state, session_results, bytes_received) do
    {processor, proc_results} = Processor.notify_bytes_received(state.processor, bytes_received)
    state = %{state | processor: processor}

    handle_proc_result(state, session_results, proc_results)
  end

  defp repeat_process_bytes(state, session_results, bytes_received) do
    {processor, proc_results} = Processor.notify_bytes_received(state.processor, bytes_received)
    state = %{state | processor: processor}

    {state, session_results} = handle_proc_result(state, session_results, proc_results)
    
    do_process_bytes(state, <<>>, session_results)
  end

  defp act_on_message(state, raw_message, results_so_far, bytes_received) do
    case RawMessage.unpack(raw_message) do
      {:error, :unknown_message_type} ->
        _ = Logger.error "#{state.session_id}: Received message of type #{raw_message.message_type_id} but we have no known way to unpack it!"

      {:ok, message} ->
        {processor, notify_results} = Processor.notify_bytes_received(state.processor, bytes_received)
        {processor, processor_results} = Processor.handle(processor, message)
        state = %{state | processor: processor}
      
        {state, results_so_far} = handle_proc_result(state, results_so_far, processor_results ++ notify_results)
        do_process_bytes(state, <<>>, results_so_far)
    end
  end

  defp handle_proc_result(state, results_so_far, []) do
    :ok = log_io_data(state, :output, results_so_far.bytes_to_send)
    {state, results_so_far}
  end

  defp handle_proc_result(state, results_so_far, [proc_result_head | proc_result_tail]) do
    case proc_result_head do
      {:response, message = %DetailedMessage{}} ->
        raw_message = RawMessage.pack(message)
        csid = get_csid_for_message_type(raw_message)

        {chunk_io, data} = ChunkIo.serialize(state.chunk_io, raw_message, csid)
        state = %{state | chunk_io: chunk_io}
        results_so_far = %{results_so_far | bytes_to_send: [results_so_far.bytes_to_send | data] }
        handle_proc_result(state, results_so_far, proc_result_tail)

      {:event, %RtmpEvents.PeerChunkSizeChanged{new_chunk_size: size}} ->
        chunk_io = ChunkIo.set_receiving_max_chunk_size(state.chunk_io, size)
        state = %{state | chunk_io: chunk_io}
        results_so_far = %{results_so_far | events: [%RtmpEvents.PeerChunkSizeChanged{new_chunk_size: size} | results_so_far.events]}
        handle_proc_result(state, results_so_far, proc_result_tail)

      {:event, %RtmpEvents.SelfChunkSizeChanged{new_chunk_size: size}} ->
        chunk_io = ChunkIo.set_sending_max_chunk_size(state.chunk_io, size)
        state = %{state | chunk_io: chunk_io}
        results_so_far = %{results_so_far | events: [%RtmpEvents.PeerChunkSizeChanged{new_chunk_size: size} | results_so_far.events]}
        handle_proc_result(state, results_so_far, proc_result_tail)

      {:event, event} ->
        results_so_far = %{results_so_far | events: [event | results_so_far.events]}
        handle_proc_result(state, results_so_far, proc_result_tail)
    end
  end

  # Csid seems to mostly be for better utilizing compression by spreading
  # different message types among different chunk stream ids.  It also allows
  # video and audio data to track different timestamps then other messages.
  # These numbers are just based on observations of current client-server activity
  defp get_csid_for_message_type(%RawMessage{message_type_id: 1}), do: 2
  defp get_csid_for_message_type(%RawMessage{message_type_id: 2}), do: 2
  defp get_csid_for_message_type(%RawMessage{message_type_id: 3}), do: 2
  defp get_csid_for_message_type(%RawMessage{message_type_id: 4}), do: 2
  defp get_csid_for_message_type(%RawMessage{message_type_id: 5}), do: 2
  defp get_csid_for_message_type(%RawMessage{message_type_id: 6}), do: 2
  defp get_csid_for_message_type(%RawMessage{message_type_id: 18}), do: 3
  defp get_csid_for_message_type(%RawMessage{message_type_id: 19}), do: 3
  defp get_csid_for_message_type(%RawMessage{message_type_id: 9}), do: 21
  defp get_csid_for_message_type(%RawMessage{message_type_id: 8}), do: 20
  defp get_csid_for_message_type(%RawMessage{message_type_id: _}), do: 6

  defp prepare_log_files(state = %State{config: %SessionConfig{io_log_mode: :none}}) do
    state
  end

  defp prepare_log_files(state = %State{config: %SessionConfig{io_log_mode: :raw_io}}) do
    path = "dumps"

    :ok = File.mkdir_p!(path)
    input = File.open!("#{path}/#{state.session_id}.input.rtmp", [:binary, :write, :exclusive])
    output = File.open!("#{path}/#{state.session_id}.output.rtmp", [:binary, :write, :exclusive])

    log_files = Map.put(state.log_files, :input_append, input)
    log_files = Map.put(log_files, :output_append, output)
    %{state | log_files: log_files}
  end

  defp log_io_data(%State{config: %SessionConfig{io_log_mode: :none}}, _input_or_output, _data) do
    :ok
  end

  defp log_io_data(_, _, <<>>) do
    :ok
  end

  defp log_io_data(state = %State{config: %SessionConfig{io_log_mode: :raw_io}}, :input, data) do
    file = Map.fetch!(state.log_files, :input_append)
    IO.binwrite(file, data)
  end

  defp log_io_data(state = %State{config: %SessionConfig{io_log_mode: :raw_io}}, :output, data) do
    file = Map.fetch!(state.log_files, :output_append)
    IO.binwrite(file, data)
  end

end