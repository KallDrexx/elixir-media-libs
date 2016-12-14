defmodule Amf3 do
  @moduledoc """
  Functions to serialize and deserialize AMF3 encoded data.

  Based on the Adobe specification found at
  http://wwwimages.adobe.com/www.adobe.com/content/dam/Adobe/en/devnet/amf/pdf/amf-file-format-spec.pdf
  """

  @spec deserialize(<<>>) :: {:ok, [any]}
  def deserialize(binary) when is_binary(binary) do
    Amf3.Deserializer.deserialize(binary)
  end

  @spec serialize(any | [any]) :: <<>>
  def serialize(values) when is_list(values), do: do_serialize(values, <<>>)
  def serialize(value),                       do: do_serialize([value], <<>>)

  defp do_serialize(_values, _accumulator) do
    raise("not implemented")
  end


end
