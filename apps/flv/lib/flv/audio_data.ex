defmodule Flv.AudioData do
  @moduledoc "Represents a packet of audio data."

  @type sound_format :: :pcm_platform_endian | :adpcm | :mp3 | :pcm_little_endian |
                        :nelly_16khz | :nelly_8khz | :nelly | :g711_alaw | :g711_mulaw |
                        :reserved | :aac | :speex | :mp3_8khz | :device_specific

  @type sample_rate :: 5 | 11 | 22 | 44
  @type sample_size :: 8 | 16
  @type channel_type :: :mono | :stereo
  @type aac_packet_type :: :sequence_header | :raw_data | :not_aac

  @type t :: %__MODULE__{
    format: sound_format,
    sample_rate_in_khz: sample_rate,
    sample_size_in_bits: sample_size,
    channel_type: channel_type,
    aac_packet_type: aac_packet_type,
    data: binary
  }

  defstruct format: nil,
            sample_rate_in_khz: nil,
            sample_size_in_bits: nil,
            channel_type: nil,
            aac_packet_type: :not_aac,
            data: <<>>

  @spec parse(binary) :: {:ok, __MODULE__.t} | :error
  @doc "Parses the provided binary into an flv video tag"
  def parse(binary) when is_binary(binary) do
    do_parse(binary)
  end

  defp do_parse(<<format_id::4, rate_id::2, size_id::1, type_id::1, rest::binary>>) do
    format = get_format(format_id)
    rate = get_rate(rate_id)
    size = get_size(size_id)
    type = get_channel_type(type_id)

    case format != :error && rate != :error && size != :error && type != :error do
      true ->
        audio = %__MODULE__{
          format: format,
          sample_rate_in_khz: rate,
          sample_size_in_bits: size,
          channel_type: type,
        }

        {:ok, apply_data(rest, audio)}

      false ->
        :error
    end

  end

  defp do_parse(_) do
    :error
  end

  defp get_format(0), do: :pcm_platform_endian
  defp get_format(1), do: :adpcm
  defp get_format(2), do: :mp3
  defp get_format(3), do: :pcm_little_endian
  defp get_format(4), do: :nelly_16khz
  defp get_format(5), do: :nelly_8khz
  defp get_format(6), do: :nelly
  defp get_format(7), do: :g711_alaw
  defp get_format(8), do: :g711_mulaw
  defp get_format(9), do: :reserved
  defp get_format(10), do: :aac
  defp get_format(11), do: :speex
  defp get_format(14), do: :mp3_8khz
  defp get_format(15), do: :device_specific
  defp get_format(_), do: :error

  defp get_rate(0), do: 5 # should be 5.5, but for some reason the typesepec is not allowing decimals
  defp get_rate(1), do: 11
  defp get_rate(2), do: 22
  defp get_rate(3), do: 44

  defp get_size(0), do: 8
  defp get_size(1), do: 16

  defp get_channel_type(0), do: :mono
  defp get_channel_type(1), do: :stereo

  defp apply_data(<<0x00, rest::binary>>, audio_data = %__MODULE__{format: :aac}) do
    %{audio_data |
      aac_packet_type: :sequence_header,
      data: rest
    }
  end

  defp apply_data(<<0x01, rest::binary>>, audio_data = %__MODULE__{format: :aac}) do
    %{audio_data |
      aac_packet_type: :raw_data,
      data: rest
    }
  end

  defp apply_data(binary, audio_data) do
    %{audio_data | data: binary}
  end
end