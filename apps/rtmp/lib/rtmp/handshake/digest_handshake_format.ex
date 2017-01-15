defmodule Rtmp.Handshake.DigestHandshakeFormat do
  @moduledoc """
  Functions to parse and validate RTMP handshakes based on flash client versions
  and SHA digests.  This handshake is required for supporting H.264 video.

  Since no documentation of this handshake publicly exists from Adobe, this
  was created by referencing https://www.cs.cmu.edu/~dst/Adobe/Gallery/RTMPE.txt
  """

  require Logger

  @random_crud <<0xf0, 0xee, 0xc2, 0x4a, 0x80, 0x68, 0xbe, 0xe8,
    0x2e, 0x00, 0xd0, 0xd1, 0x02, 0x9e, 0x7e, 0x57,
    0x6e, 0xec, 0x5d, 0x2d, 0x29, 0x80, 0x6f, 0xab,
    0x93, 0xb8, 0xe6, 0x36, 0xcf, 0xeb, 0x31, 0xae>>

  @genuine_fms_name "Genuine Adobe Flash Media Server 001"
  @genuine_player_name "Genuine Adobe Flash Player 001"
  @genuine_fms_with_crud @genuine_fms_name <> @random_crud
  @genuine_player_with_crud @genuine_player_name <> @random_crud

  @sha_256_digest_length 32

  @adobe_version <<128, 0, 7, 2>> # copied from jwplayer handshake

  @type state :: %__MODULE__.State{}

  defmodule State do
    @moduledoc false

    defstruct current_stage: :p0,
              unparsed_binary: <<>>,
              bytes_to_send: <<>>,
              received_start_time: 0,
              is_server: nil
  end

  @spec new() :: state
  @doc "Creates a new digest handshake format instance"
  def new() do
    %State{}
  end

  @spec is_valid_format(binary) :: :unknown | :yes | :no
  @doc "Validates if the passed in binary can be parsed using the digest handshake."
  def is_valid_format(binary) do
    cond do
      byte_size(binary) < 1537 -> :unknown
      <<type::8, c1::bytes-size(1536), _::binary>> = binary ->
        fms_version = get_message_format(c1, @genuine_fms_name)
        player_version = get_message_format(c1, @genuine_player_name)

        cond do
          type != 3 -> :no
          fms_version == :version1 || fms_version == :version2 -> :yes
          player_version == :version1 || player_version == :version2 -> :yes
          true -> :no
        end
    end
  end

  @spec process_bytes(state, binary) :: {state, Rtmp.Handshake.process_result}
  @doc "Attempts to proceed with the handshake process with the passed in bytes"
  def process_bytes(state = %State{}, binary) do
    state = %{state | unparsed_binary: state.unparsed_binary <> binary}
    do_process_bytes(state)
  end

  @spec create_p0_and_p1_to_send(state) :: {state, binary}
  @doc "Returns packets 0 and 1 to send to the peer"
  def create_p0_and_p1_to_send(state = %State{}) do
    random_binary = :crypto.strong_rand_bytes(1528)
    handshake = <<0::4 * 8>> <> @adobe_version <> random_binary

    {state, digest_offset, constant_key} = case state.is_server do
      nil ->
        # Since this is called prior to us knowing if we are a server or not
        # (i.e. we haven't received peer's packet 1 yet) we assume we are
        # the first to send a packet off and thus we are the client
        state = %{state | is_server: false}
        digest_offset = get_client_digest_offset(handshake)
        {state, digest_offset, @genuine_player_name}

      true ->
        digest_offset = get_server_digest_offset(handshake)
        {state, digest_offset, @genuine_fms_name}
    end

    {part1, _, part2} = get_message_parts(handshake, digest_offset)
    hmac = calc_hmac(part1, part2, constant_key)

    p0 = <<3::8>>
    p1 = part1 <> hmac <> part2
    {state, p0 <> p1}
  end

  defp do_process_bytes(state = %State{current_stage: :p0}) do
    if byte_size(state.unparsed_binary) < 1 do
      {state, {:incomplete, <<>>}}
    else
      <<type::8, rest::binary>> = state.unparsed_binary
      case type do
        3 ->
          state = %{state | unparsed_binary: rest, current_stage: :p1}
          do_process_bytes(state)

        _ ->
          {state, :failure}
      end
    end
  end

  defp do_process_bytes(state = %State{current_stage: :p1, is_server: nil}) do
    # Since is_server is nil, that means we got packet 1 from the peer before we sent
    # our packet 1.  This means we are a server reacting to a client
    {state, p0_and_p1} = create_p0_and_p1_to_send(%{state | is_server: true})
    state = %{state | bytes_to_send: state.bytes_to_send <> p0_and_p1 }

    do_process_bytes(state)
  end

  defp do_process_bytes(state = %State{current_stage: :p1}) do
    if byte_size(state.unparsed_binary) < 1536 do
      send_incomplete_response(state)
    else
      <<handshake::bytes-size(1536), rest::binary>> = state.unparsed_binary
      const_to_use = case state.is_server do
        true -> @genuine_player_name
        false -> @genuine_fms_name
      end

      {challenge_key_offset, key_offset} = case get_message_format(handshake, const_to_use) do
        :version1 -> {get_client_digest_offset(handshake), get_client_dh_offset(handshake)}
        :version2 -> {get_server_digest_offset(handshake), get_server_dh_offset(handshake)}
      end

      <<_::bytes-size(challenge_key_offset), challenge_key::bytes-size(32), _::binary>> = handshake

      key_offset_without_time = key_offset - 4
      <<
        time::4 * 8,
        _::bytes-size(key_offset_without_time),
        _key::bytes-size(128),
        _::binary
      >> = handshake

      state = %{state |
        received_start_time: time,
        current_stage: :p2,
        bytes_to_send: state.bytes_to_send <> generate_p2(state.is_server, challenge_key),
        unparsed_binary: rest
      }

      do_process_bytes(state)
    end
  end

  defp do_process_bytes(state = %State{current_stage: :p2}) do
    if byte_size(state.unparsed_binary) < 1536 do
      send_incomplete_response(state)
    else
      # TODO: Add confirmation of the p1 public key we sent.  For now
      # we are just assuming that if the peer didn't disconnect us we
      # are good

      <<_::1536 * 8, rest::binary>> = state.unparsed_binary
      state = %{state | unparsed_binary: rest}
      {state, {:success, state.received_start_time, state.bytes_to_send, state.unparsed_binary}}
    end
  end

  defp generate_p2(is_server, challenge_key) do
    random_binary = :crypto.strong_rand_bytes(1536 - @sha_256_digest_length)
    string = case is_server do
      true -> @genuine_fms_with_crud
      false -> @genuine_player_with_crud
    end

    digest = :crypto.hmac(:sha256, string, challenge_key)
    signature = :crypto.hmac(:sha256, digest, random_binary)

    random_binary <> signature
  end

  defp get_server_dh_offset(<<_::bytes-size(766), byte1, byte2, byte3, byte4, _::binary>>) do
    # Calculates the offset of the server's Diffie-Hellman key
    offset = byte1 + byte2 + byte3 + byte4
    rem(offset, 632) + 8
  end

  defp get_server_digest_offset(<<_::bytes-size(772), byte1, byte2, byte3, byte4, _::binary>>) do
    # Calculates the offset of the server's digest
    offset = byte1 + byte2 + byte3 + byte4
    rem(offset, 728) + 776
  end

  defp get_client_dh_offset(<<_::bytes-size(1532), byte1, byte2, byte3, byte4, _::binary>>) do
    # Calculates the offset of the client's Diffie-Hellmann key
    offset = byte1 + byte2 + byte3 + byte4
    rem(offset, 632) + 772
  end

  defp get_client_digest_offset(<<_::bytes-size(8), byte1, byte2, byte3, byte4, _::binary>>) do
    # Calculates the offset of the client's digest
    offset = byte1 + byte2 + byte3 + byte4
    rem(offset, 728) + 12
  end

  defp get_message_format(handshake, key) do
    version_1_offset = get_client_digest_offset(handshake)
    {v1_part1, v1_digest, v1_part2} = get_message_parts(handshake, version_1_offset)
    v1_hmac = calc_hmac(v1_part1, v1_part2, key)

    version_2_offset = get_server_digest_offset(handshake)
    {v2_part1, v2_digest, v2_part2} = get_message_parts(handshake, version_2_offset)
    v2_hmac = calc_hmac(v2_part1, v2_part2, key)

    cond do
      v1_hmac == v1_digest -> :version1
      v2_hmac == v2_digest -> :version2
      true -> :unknown
    end
  end

  defp get_message_parts(handshake, digest_offset) do
    after_digest = 1536 - (digest_offset + @sha_256_digest_length)

    <<
      part1::bytes-size(digest_offset),
      digest::bytes-size(@sha_256_digest_length),
      part2::bytes-size(after_digest),
      _::binary
    >> = handshake

    {part1, digest, part2}
  end

  defp calc_hmac(part1, part2, key) do
    data = part1 <> part2
    :crypto.hmac(:sha256, key, data)
  end

  defp send_incomplete_response(state) do
    bytes_to_send = state.bytes_to_send
    state = %{state | bytes_to_send: <<>>}
    {state, {:incomplete, bytes_to_send}}
  end

end