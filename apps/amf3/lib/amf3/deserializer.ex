defmodule Amf3.Deserializer do
  use Bitwise

  @spec deserialize(<<>>) :: [any]
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

  defp do_deserialize(<<0x04, rest::binary>>, accumulator) do
    {value, rest} = get_u29(rest)

    do_deserialize(rest, [u29_to_i29(value) | accumulator])
  end

  defp do_deserialize(<<0x05, value::float-64, rest::binary>>, accumulator) do
    do_deserialize(rest, [value | accumulator])
  end

  defp get_u29(<<0::1, byte::7, rest::binary>>) do
    {byte, rest}
  end

  defp get_u29(<<1::1, b1::7, 0::1, b2::7, rest::binary>>) do
    value = Bitwise.bsl(b1, 7)
    |> Bitwise.bor(b2)

    {value, rest}
  end

  defp get_u29(<<1::1, b1::7, 1::1, b2::7, 0::1, b3::7, rest::binary>>) do
    value = Bitwise.bsl(b1, 14)
    |> Bitwise.bor(Bitwise.bsl(b2, 7))
    |> Bitwise.bor(b3)

    {value, rest}
  end

  defp get_u29(<<1::1, b1::7, 1::1, b2::7, 1::1, b3::7, b4, rest::binary>>) do
    value = Bitwise.bsl(b1,22)
    |> Bitwise.bor(Bitwise.bsl(b2, 15))
    |> Bitwise.bor(Bitwise.bsl(b3, 8))
    |> Bitwise.bor(b4)

    {value, rest}
  end

  # If the u29's first bit is 1 (> :math.pow(2,28), then subtract the value from :math.pow(2,39)
  defp u29_to_i29(value) when value > 268435455, do: value - 536870912
  defp u29_to_i29(value),                        do: value
end