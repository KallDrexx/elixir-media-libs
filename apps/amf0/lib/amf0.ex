defmodule Amf0 do
  @moduledoc """
  Functions for serializing and deserializing AMF0 encoded data
  """

  @doc """
  Deserializes data from amf0 encoded binary

  ## Examples

      iex> Amf0.deserialize(<<0::8, 532::float-64, 1::8, 1::8>>)
      {:ok, [532.0, true]}

  """
  @spec deserialize(<<>>) :: {:ok, [any()]}
  def deserialize(binary) when is_binary(binary) do
    do_deserialize(binary, [])
  end

  @doc """
  Serializes the passed in values into AMF0 encoded binary

  ## Examples

      iex> Amf0.serialize("test")
      <<2::8, 4::16>> <> "test"

      iex> Amf0.serialize([532, true])
      <<0::8, 532::float-64, 1::8, 1::8>>
  """
  @spec serialize(any() | [any()]) :: <<>>
  def serialize(values) when is_list(values), do: do_serialize(values, <<>>)
  def serialize(value), do: do_serialize([value], <<>>)

  defp do_deserialize(<<>>, accumulator) do
    {:ok, Enum.reverse(accumulator)}
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
      6 -> :undefined
      8 -> :emca_array
    end
  end

  defp get_object(:number, <<number::float-64, rest::binary>>) do
    {number, rest}
  end
  
  defp get_object(:boolean, <<bool::8, rest::binary>>) do
    atom = if bool == 1, do: true, else: false
    {atom, rest}
  end
  
  defp get_object(:"utf8-1", <<length::16, binary::binary>>) do
    <<string::binary-size(length), rest::binary>> = binary
    {string, rest}
  end
  
  defp get_object(:null, binary) do
    {nil, binary}
  end

  defp get_object(:undefined, binary) do
    {nil, binary}
  end

  defp get_object(:emca_array, binary) do
    <<_::32, binary::binary>> = binary

    {properties, rest} = get_object_properties(binary, %{})
    {properties, rest}
  end
  
  defp get_object(:object, binary) do
    {properties, rest} = get_object_properties(binary, %{})    
    {properties, rest}
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
  
  defp do_serialize([value | rest], binary) when is_number(value) do
    do_serialize(rest, binary <> <<0::8, value::float-64>>)
  end
  
  defp do_serialize([value | rest], binary) when is_boolean(value) do
    bit = if value, do: 1, else: 0
    
    do_serialize(rest, binary <> <<1::8, bit::8>>)
  end
  
  defp do_serialize([value | rest], binary) when is_binary(value) do
    length = String.length(value)
        
    do_serialize(rest, binary <> <<2::8, length::16>> <> value)
  end
  
  defp do_serialize([nil | rest], binary) do
    do_serialize(rest, binary <> <<5::8>>)
  end
  
  defp do_serialize([properties | rest], binary) when is_map(properties) do
    serialized_properties = Enum.map(Map.keys(properties), fn(x) -> serialize_property(x, Map.get(properties, x)) end)
    |> Enum.reduce(fn(x, acc) -> acc <> x end)
        
    do_serialize(rest, binary <> <<3>> <> serialized_properties <> <<0, 0, 9>>)
  end
  
  defp serialize_property(name, value) do
    length = byte_size(name)
    binary = <<length::16>> <> name
    
    do_serialize([value], binary)
  end

end