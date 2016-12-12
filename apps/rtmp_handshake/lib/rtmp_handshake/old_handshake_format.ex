defmodule RtmpHandshake.OldHandshakeFormat do
  @moduledoc """
  Functions to parse and validate RTMP handshakes as specified in the
  official RTMP specification.

  This handshake format does *NOT* work for h.264 video.
  """

  @behaviour RtmpHandshake

  require Logger

  defmodule State do
    defstruct random_data: <<>>,
              current_stage: :p0,
              unparsed_binary: <<>>,
              bytes_to_send: <<>>,
              received_start_time: 0
  end

  @doc "Creates a new old handshake format instance"
  def new() do
    %State{}
  end

  @doc "Validates if the passed in binary can be parsed using the old style handshake."
  def is_valid_format(binary) do
    case byte_size(binary) >= 16 do
      false -> :unknown
      true ->
        case binary do
          <<3::1 * 8, _::4 * 8, 0::4 * 8, _::binary>> -> :yes
          _ -> :no
        end
    end
  end

  @doc "Attempts to proceed with the handshake process with the passed in bytes"
  def process_bytes(state = %State{}, binary) do
    state = %{state | unparsed_binary: state.unparsed_binary <> binary}
    do_process_bytes(state)
  end

  @doc "Returns packets 0 and 1 to send to the peer"
  def create_p0_and_p1_to_send(state = %State{}) do
    state = %{state | random_data: generate_random_binary(1528, <<>>)}
    p0 = <<3::8>>
    p1 = <<0::4 * 8, 0::4 * 8>> <> state.random_data # local start time is alawys zero
    {state, p0 <> p1}
  end

  defp do_process_bytes(state = %State{current_stage: :p0}) do
    if byte_size(state.unparsed_binary) < 1 do
      send_incomplete_response(state)
    else
      case state.unparsed_binary do
        <<3::8, rest::binary>> ->
          state = %{state |
            unparsed_binary: rest,
            current_stage: :p1
          }

          do_process_bytes(state)

        _ -> {state, :failure}
      end
    end
  end

  defp do_process_bytes(state = %State{current_stage: :p1}) do
    if byte_size(state.unparsed_binary) < 1536 do
      send_incomplete_response(state)
    else
      case state.unparsed_binary do
        <<time::4 * 8, 0::4 * 8, random::binary-size(1528), rest::binary>> ->
          state = %{state |
            bytes_to_send: state.bytes_to_send <> <<time::4 * 8, 0::4 * 8>> <> random, # packet 2
            unparsed_binary: rest,
            received_start_time: time,
            current_stage: :p2
          }

          do_process_bytes(state)

        _ ->
          bytes_to_send = state.bytes_to_send
          state = %{state | bytes_to_send: <<>>}
          {state, {:incomplete, bytes_to_send}}
      end
    end
  end

  defp do_process_bytes(state = %State{current_stage: :p2}) do
    if byte_size(state.unparsed_binary) < 1536 do
      send_incomplete_response(state)
    else

      expected_random = state.random_data
      random_size = byte_size(expected_random)

      case state.unparsed_binary do
        <<0::4 * 8, _::4 * 8, ^expected_random::size(random_size)-binary, rest::binary>> ->
          bytes_to_send = state.bytes_to_send
          state = %{state | unparsed_binary: <<>>, current_stage: :complete, bytes_to_send: <<>>}
          {state, {:success, state.received_start_time, bytes_to_send, rest}}

        _ ->
          {state, :failure}
      end
    end
  end

  defp send_incomplete_response(state) do
    bytes_to_send = state.bytes_to_send
    state = %{state | bytes_to_send: <<>>}
    {state, {:incomplete, bytes_to_send}}
  end

  defp generate_random_binary(0, accumulator),     do: accumulator
  defp generate_random_binary(count, accumulator), do: generate_random_binary(count - 1,  accumulator <> <<:random.uniform(254)>> )
  
end