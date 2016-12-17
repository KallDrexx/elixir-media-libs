defmodule RtmpHandshake do
  @moduledoc """
  Provides functionality to handle the RTMP handshake process
  """

  require Logger

  alias RtmpHandshake.OldHandshakeFormat, as: OldHandshakeFormat
  alias RtmpHandshake.ParseResult, as: ParseResult
  alias RtmpHandshake.HandshakeResult, as: HandshakeResult
  alias RtmpHandshake.DigestHandshakeFormat, as: DigestHandshakeFormat

  @type handshake_type :: :unknown | :old | :digest
  @type is_valid_format_result :: :yes | :no | :unknown
  @type start_time :: non_neg_integer
  @type remaining_binary :: <<>>
  @type binary_response :: <<>>
  @type behaviour_state :: any
  @type process_result :: {:success, start_time, binary_response, remaining_binary}
                          | {:incomplete, binary_response}
                          | :failure

  @callback is_valid_format(<<>>) :: is_valid_format_result
  @callback process_bytes(behaviour_state, <<>>) :: {behaviour_state, process_result}
  @callback create_p0_and_p1_to_send(behaviour_state) :: {behaviour_state, <<>>}

  defmodule State do
    defstruct status: :pending,
              handshake_state: nil,
              handshake_type: :unknown,
              remaining_binary: <<>>,
              peer_start_timestamp: nil
  end

  @doc """
  Creates a new finite state machine to handle the handshake process,
    and preliminary parse results, including the initial x0 and x1
    binary to send to the peer.
  """
  @spec new(handshake_type) :: {%State{}, ParseResult.t}
  def new(:old) do
    {handshake_state, bytes_to_send} =
      OldHandshakeFormat.new()
      |> OldHandshakeFormat.create_p0_and_p1_to_send()

    state = %State{handshake_type: :old, handshake_state: handshake_state}
    result = %ParseResult{current_state: :waiting_for_data, bytes_to_send: bytes_to_send}
    {state, result}
  end

  def new(:digest) do
    {handshake_state, bytes_to_send} =
      DigestHandshakeFormat.new()
      |> DigestHandshakeFormat.create_p0_and_p1_to_send()

    state = %State{handshake_type: :digest, handshake_state: handshake_state}
    result = %ParseResult{current_state: :waiting_for_data, bytes_to_send: bytes_to_send}
    {state, result}
  end

  def new(:unknown) do
    state = %State{handshake_type: :unknown}
    {state, %ParseResult{current_state: :waiting_for_data}}
  end

  @doc "Reads the passed in binary to proceed with the handshaking process"
  @spec process_bytes(%State{}, <<>>) :: {%State{}, ParseResult.t}
  def process_bytes(state = %State{handshake_type: :unknown}, binary) when is_binary(binary) do
    state = %{state | remaining_binary: state.remaining_binary <> binary}
    is_old_format = OldHandshakeFormat.is_valid_format(state.remaining_binary)
    is_digest_format = DigestHandshakeFormat.is_valid_format(state.remaining_binary)

    case {is_old_format, is_digest_format} do
#      {_, :yes} ->
#        Logger.debug("Digest format")
#        handshake_state = DigestHandshakeFormat.new()
#
#        binary = state.remaining_binary
#        state = %{state |
#          remaining_binary: <<>>,
#          handshake_type: :digest,
#          handshake_state: handshake_state
#        }
#
#        # Processing bytes should trigger p0 and p1 to be sent
#        {state, result} = process_bytes(state, binary)
#        result = %{result | bytes_to_send: result.bytes_to_send}
#        {state, result}

      {:yes, _} ->
        Logger.debug("Old format")
        {handshake_state, bytes_to_send} =
          OldHandshakeFormat.new()
          |> OldHandshakeFormat.create_p0_and_p1_to_send()

        binary = state.remaining_binary
        state = %{state |
          remaining_binary: <<>>,
          handshake_type: :old,
          handshake_state: handshake_state
        }

        Logger.debug("Bytes to send: #{inspect(bytes_to_send)}")

        {state, result} = process_bytes(state, binary)
        result = %{result | bytes_to_send: bytes_to_send <> result.bytes_to_send}
        {state, result}

      {:no, :no} ->
        # No known handhsake format
        Logger.debug("Unknown format")
        {state, %ParseResult{current_state: :failure}}

      _ ->
        {state, %ParseResult{}}
    end
  end

  def process_bytes(state = %State{handshake_type: :old}, binary) when is_binary(binary) do
    case OldHandshakeFormat.process_bytes(state.handshake_state, binary) do
      {handshake_state, :failure} ->
        state = %{state | handshake_state: handshake_state}
        {state, %ParseResult{current_state: :failure}}

      {handshake_state, {:incomplete, bytes_to_send}} ->
        state = %{state | handshake_state: handshake_state}
        {state, %ParseResult{current_state: :waiting_for_data, bytes_to_send: bytes_to_send}}

      {handshake_state, {:success, start_time, response, remaining_binary}} ->
        state = %{state |
          handshake_state: handshake_state,
          remaining_binary: remaining_binary,
          peer_start_timestamp: start_time,
          status: :complete
        }

        result = %ParseResult{current_state: :success, bytes_to_send: response}
        {state, result}
    end
  end

  def process_bytes(state = %State{handshake_type: :digest}, binary) when is_binary(binary) do
    case DigestHandshakeFormat.process_bytes(state.handshake_state, binary) do
      {handshake_state, :failure} ->
        state = %{state | handshake_state: handshake_state}
        {state, %ParseResult{current_state: :failure}}

      {handshake_state, {:incomplete, bytes_to_send}} ->
        state = %{state | handshake_state: handshake_state}
        {state, %ParseResult{current_state: :waiting_for_data, bytes_to_send: bytes_to_send}}

      {handshake_state, {:success, start_time, response, remaining_binary}} ->
        state = %{state |
          handshake_state: handshake_state,
          remaining_binary: remaining_binary,
          peer_start_timestamp: start_time,
          status: :complete
        }

        result = %ParseResult{current_state: :success, bytes_to_send: response}
        {state, result}
    end
  end

  @doc """
  After a handshake has been successfully completed it is called to 
    retrieve the peer's starting timestamp and any left over binary that
    may need to be parsed later (not part of the handshake but instead part
    of the rtmp protocol).
  """
  @spec get_handshake_result(%State{}) :: {%State{}, HandshakeResult.t}
  def get_handshake_result(state = %State{status: :complete}) do
    unparsed_binary = state.remaining_binary
    
    {
      %{state | remaining_binary: <<>>},
      %HandshakeResult{
        peer_start_timestamp: state.peer_start_timestamp, 
        remaining_binary: unparsed_binary
      }
    }
  end

end
