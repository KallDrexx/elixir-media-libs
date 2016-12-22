defmodule Amf3 do
  @moduledoc """
  Functions to serialize and deserialize AMF3 encoded data.

  Based on the Adobe specification found at
  http://wwwimages.adobe.com/www.adobe.com/content/dam/Adobe/en/devnet/amf/pdf/amf-file-format-spec.pdf
  """

  @spec deserialize(<<>>) :: [false | nil | true | number]
  def deserialize(binary) when is_binary(binary) do
    Amf3.Deserializer.deserialize(binary)
  end

end
