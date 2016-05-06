defmodule RtmpCommon.Amf0 do
  @moduledoc "Deals with AMF0 encoding"
  
  def deserialize(binary) do
    do_deserialize(binary, [])
  end
  
  defp do_deserialize(<<>>, accumulator) do
    Enum.reverse(accumulator)
  end
  
  defp do_deserialize(<<marker::8, binary::binary>>, accumulator) do
    get_marker_type(marker)
    |> get_object(binary)
    |> do_deserialize(accumulator)
  end
  
  defp do_deserialize({object, binary}, accumulator) do
    # Transforms the get_object results for readability into the
    # proper arguments for do_deserialize
    do_deserialize(binary, [object | accumulator])
  end
  
  defp get_marker_type(marker_number) do
    case marker_number do
      0 -> :number
      1 -> :boolean
      2 -> :"utf8-1" # TODO: support other utf8 markers
      3 -> :object
    end
  end
   
  defp get_object(:number, <<number::64, rest::binary>>) do
    {%RtmpCommon.Amf0.Object{type: :number, value: number}, rest}
  end
  
  defp get_object(:boolean, <<bool::8, rest::binary>>) do
    atom = if bool == 1, do: true, else: false
    {%RtmpCommon.Amf0.Object{type: :boolean, value: atom}, rest}
  end
  
  defp get_object(:"utf8-1", <<length::16, binary::binary>>) do
    <<string::binary-size(length), rest::binary>> = binary
    {%RtmpCommon.Amf0.Object{type: :string, value: string}, rest}
  end
  
  # Objects
  defp get_object(:object, binary) do
    {properties, rest} = get_object_properties(binary, %{})    
    {%RtmpCommon.Amf0.Object{type: :object, value: properties}, rest}
  end
  
  defp get_object_properties(<<0, 0, 9, binary::binary>>, properties) do
    {properties, binary}
  end
  
  defp get_object_properties(<<length::16, binary::binary>>, properties) do
    <<name::binary-size(length), type_marker::8, rest::binary>> = binary
    
    get_marker_type(type_marker)
    |> get_object(rest)
    |> form_object_property(name, properties)
  end
  
  defp form_object_property({object, binary}, property_name, properties) do
    get_object_properties(binary, Map.put(properties, property_name, object))
  end
  
end