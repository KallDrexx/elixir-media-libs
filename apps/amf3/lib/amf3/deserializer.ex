defmodule Amf3.Deserializer do

  @spec deserialize(<<>>) :: {:ok, [any]}
  def deserialize(binary) do
    do_deserialize(binary, [])
  end

  defp do_deserialize(<<>>, accumulator) do
    Enum.reverse(accumulator)
  end

  defp do_deserialize(<<0x00, rest::binary>>, accumulator) do
    do_deserialize(rest, [nil | accumulator])
  end

  defp do_deserialize(<<0x01, rest::binary>>, accumulator) do
    do_deserialize(rest, [nil | accumulator])
  end

  defp do_deserialize(<<0x02, rest::binary>>, accumulator) do
    do_deserialize(rest, [false | accumulator])
  end

  defp do_deserialize(<<0x03, rest::binary>>, accumulator) do
    do_deserialize(rest, [true | accumulator])
  end

  defp do_deserialize(<<0x04, byte, rest::binary>>, accumulator) when byte < 0x80 do
    do_deserialize(rest, [byte | accumulator])
  end

  defp do_deserialize(<<0x04, byte1, byte2, rest::binary>>, accumulator) when byte2 < 0x80 do
    <<value::2 * 8>> = <<byte1, byte2>>
    do_deserialize(rest, [value | accumulator])
  end

  defp do_deserialize(<<0x04, byte1, byte2, byte3, rest::binary>>, accumulator) when byte3 < 0x80 do
    <<value::3 * 8>> = <<byte1, byte2, byte3>>
    do_deserialize(rest, [value | accumulator])
  end

  defp do_deserialize(<<0x04, byte1, byte2, byte3, byte4, rest::binary>>, accumulator) do
    <<value::4 * 8>> = <<byte1, byte2, byte3, byte4>>
    do_deserialize(rest, [value | accumulator])
  end

  defp do_deserialize(<<0x05, value::float-64, rest::binary>>, accumulator) do
    do_deserialize(rest, [value | accumulator])
  end
end