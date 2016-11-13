defmodule RtmpHandshake do
  @moduledoc """
  Provides functionality to handle the RTMP handshake process
  """

  require Logger

  defmodule State do
    defstruct current_state: :waiting_for_p0,
              unparsed_binary: <<>>,
              peer_start_timestamp: nil,
              random_data: <<>>
  end

  @doc """
  Creates a new finite state machine to handle the handshake process,
    and preliminary parse results, including the initial x0 and x1
    binary to send to the peer.
  """
  @spec new() :: {%State{}, RtmpHandshake.ParseResult.t}
  def new() do
    state = %State{random_data: generate_random_binary(1528, <<>>)}
    p0 = <<3::8>>
    p1 = <<0::4 * 8, 0::4 * 8>> <> state.random_data # local start time is alawys zero
    {state, %RtmpHandshake.ParseResult{current_state: :waiting_for_data, bytes_to_send: p0 <> p1}}
  end

  @doc "Reads the passed in binary to proceed with the handshaking process"
  @spec process_bytes(%State{}, <<>>) :: {%State{}, RtmpHandshake.ParseResult.t}
  def process_bytes(state = %State{}, binary) when is_binary(binary) do

    binary = state.unparsed_binary <> binary
   
    %{state | unparsed_binary: <<>>} 
    |> do_process(binary)
  end

  @doc """
  After a handshake has been successfully completed it is called to 
    retrieve the peer's starting timestamp and any left over binary that
    may need to be parsed later (not part of the handshake but instead part
    of the rtmp protocol).
  """
  @spec get_handshake_result(%State{}) :: {%State{}, RtmpHandshake.HandshakeResult.t}
  def get_handshake_result(state = %State{current_state: :complete}) do
    unparsed_binary = state.unparsed_binary
    
    {
      %{state | unparsed_binary: <<>>},
      %RtmpHandshake.HandshakeResult{
        peer_start_timestamp: state.peer_start_timestamp, 
        remaining_binary: unparsed_binary
      }
    }
  end

  defp generate_random_binary(0, accumulator),     do: accumulator
  defp generate_random_binary(count, accumulator), do: generate_random_binary(count - 1,  accumulator <> <<:random.uniform(254)>> )

  defp do_process(state, <<>>),                                            do: do_process_fallthrough(state)
  defp do_process(state = %State{current_state: :waiting_for_p0}, binary), do: do_process_waiting_for_p0(state, binary)
  defp do_process(state = %State{current_state: :waiting_for_p1}, binary), do: do_process_waiting_for_p1(state, binary)
  defp do_process(state = %State{current_state: :waiting_for_p2}, binary), do: do_process_waiting_for_p2(state, binary)

  defp do_process_fallthrough(state) do
    {state, %RtmpHandshake.ParseResult{current_state: :waiting_for_data}}
  end

  defp do_process_waiting_for_p0(state, binary) do
    case binary do
      <<3::8, rest::binary>> -> 
        %{state | current_state: :waiting_for_p1}
        |> do_process(rest)

      _ -> {state, %RtmpHandshake.ParseResult{current_state: :failure}}
    end
  end

  defp do_process_waiting_for_p1(state, binary) do
    if byte_size(binary) < 1536 do
      {%{state | unparsed_binary: binary},  %RtmpHandshake.ParseResult{current_state: :waiting_for_data}}
    else
      <<time::4 * 8, _::4 * 8, random::binary-size(1528), rest::binary>> = binary
      binary_response = <<time::4 * 8, 0::4 * 8>> <> random # send packet 2

      {new_state, parse_result} = 
        %{state | current_state: :waiting_for_p2, peer_start_timestamp: time}
        |> do_process(rest)

      {new_state, %{parse_result | bytes_to_send: binary_response <> parse_result.bytes_to_send}}
    end
  end

  defp do_process_waiting_for_p2(state, binary) do
    if byte_size(binary) < 1536 do
      {%{state | unparsed_binary: binary},  %RtmpHandshake.ParseResult{current_state: :waiting_for_data}}
    else
      expected_random = state.random_data
      random_size = byte_size(expected_random)

      case binary do
        <<0::4 * 8, _::4 * 8, ^expected_random::size(random_size)-binary, rest::binary>> ->

          {
            %{state | current_state: :complete, unparsed_binary: rest}, 
            %RtmpHandshake.ParseResult{current_state: :success}
          }

        _ ->
          <<_::4*8, _::4*8, received_random::binary>> = binary
          {state, %RtmpHandshake.ParseResult{current_state: :failure}}
      end
    end
  end

end
