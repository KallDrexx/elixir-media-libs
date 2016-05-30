defmodule RtmpCommon.Amf0 do
  @moduledoc "Deals with AMF0 encoding"
  
  def deserialize(binary) do
    do_deserialize(binary, [])
  end
  
  def serialize(objects) when is_list(objects), do: do_serialize(objects, <<>>)
  def serialize(object), do: do_serialize([object], <<>>)
  
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
      5 -> :null
    end
  end
   
  defp get_object(:number, <<number::float-64, rest::binary>>) do
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
  
  defp get_object(:null, binary) do
    {%RtmpCommon.Amf0.Object{type: :null, value: nil}, binary}
  end
  
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
  
  defp do_serialize([], binary) do
    binary
  end
  
  defp do_serialize([%RtmpCommon.Amf0.Object{type: :number, value: value} | rest], binary) do
    do_serialize(rest, binary <> <<0::8, value::float-64>>)
  end
  
  defp do_serialize([%RtmpCommon.Amf0.Object{type: :boolean, value: value} | rest], binary) do
    bit = if value, do: 1, else: 0
    
    do_serialize(rest, binary <> <<1::8, bit::8>>)
  end
  
  defp do_serialize([%RtmpCommon.Amf0.Object{type: :string, value: value} | rest], binary) do
    length = String.length(value)
        
    do_serialize(rest, binary <> <<2::8, length::16>> <> value)
  end
  
  defp do_serialize([%RtmpCommon.Amf0.Object{type: :null, value: _} | rest], binary) do
    do_serialize(rest, binary <> <<5::8>>)
  end
  
  defp do_serialize([%RtmpCommon.Amf0.Object{type: :object, value: properties} | rest], binary) when is_map(properties) do
    serialized_properties = Enum.map(Map.keys(properties), fn(x) -> serialize_property(x, Map.get(properties, x)) end)
    |> Enum.reduce(fn(x, acc) -> acc <> x end)
        
    do_serialize(rest, binary <> <<3>> <> serialized_properties <> <<0, 0, 9>>)
  end
  
  defp serialize_property(name, object = %RtmpCommon.Amf0.Object{}) do
    length = byte_size(name)
    binary = <<length::16>> <> name
    
    do_serialize([object], binary)
  end
  
end