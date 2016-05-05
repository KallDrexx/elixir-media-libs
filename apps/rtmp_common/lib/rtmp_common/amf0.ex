defmodule RtmpCommon.Amf0 do
  @moduledoc "Deals with AMF0 encoding"
  
  def deserialize(binary) do
    do_deserialize(binary, [])
  end
  
  defp do_deserialize(<<>>, accumulator) do
    Enum.reverse(accumulator)
  end
  
  # Number
  defp do_deserialize(<<0::8, binary::binary>>, accumulator) do
    <<number::64, rest::binary>> = binary 
    
    do_deserialize(rest, [%RtmpCommon.Amf0.Object{type: :number, value: number} | accumulator])
  end
  
  # Boolean
  defp do_deserialize(<<1::8, binary::binary>>, accumulator) do
    <<bool::8, rest::binary>> = binary
    atom = if bool == 1, do: true, else: false
    
    do_deserialize(rest, [%RtmpCommon.Amf0.Object{type: :boolean, value: atom} | accumulator])
  end
  
  # Strings
  defp do_deserialize(<<2::8, binary::binary>>, accumulator) do
    {string, rest} = get_string(binary)
    do_deserialize(rest, [%RtmpCommon.Amf0.Object{type: :string, value: string} | accumulator])
  end
  
  ## UTF8-1 string
  defp get_string(<<length::8, binary::binary>>) when length <= 0x0f do
    <<string::binary-size(length), rest::binary>> = binary
    {string, rest}
  end
end