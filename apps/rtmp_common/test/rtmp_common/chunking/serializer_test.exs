defmodule RtmpCommon.Chunking.SerializerTest do
  use ExUnit.Case, async: true
  alias RtmpCommon.Chunking.Serializer, as: Serializer
  
  defmodule TestMessage do
    defstruct data: <<>>
    
    def serialize(message = %__MODULE__{}) do
      {:ok, %RtmpCommon.Messages.SerializedMessage{
        message_type_id: 3,
        data: message.data
      }}
    end
  end
  
  test "Serialize: Initial chunk for csid" do
    message = %TestMessage{data: <<152::size(100)-unit(8)>>}
    
    {_, binary} = Serializer.new() |> Serializer.serialize(72, 50, message, 55)
      
    expected_binary = <<0::2, 50::6, 72::size(3)-unit(8), 100::size(3)-unit(8), 
                        3::8, 55::size(4)-unit(8), 152::size(100)-unit(8)>>
                        
    assert expected_binary == binary
  end
  
  test "Serialize: 2nd chunk, same sid, different message length" do
    message1 = %TestMessage{data: <<152::size(100)-unit(8)>>}
    message2 = %TestMessage{data: <<152::size(101)-unit(8)>>}
    
    {serializer, _} = Serializer.new() |> Serializer.serialize(72, 50, message1, 55)
    {_, binary} = Serializer.serialize(serializer, 82, 50, message2, 55)
    
    expected_binary = <<0::2, 50::6, 10::size(3)-unit(8), 101::size(3)-unit(8), 
                        3::8, 152::size(101)-unit(8)>>
                        
    assert expected_binary == binary
  end
  
  test "Serialize: 2nd chunk, same sid, message length, and type id" do
    message = %TestMessage{data: <<152::size(100)-unit(8)>>}
    
    {serializer, _} = Serializer.new() |> Serializer.serialize(72, 50, message, 55)
    {_, binary} = Serializer.serialize(serializer, 82, 50, message, 55)
    
    expected_binary = <<0::2, 50::6, 10::size(3)-unit(8), 152::size(100)-unit(8)>>
                            
    assert expected_binary == binary
  end
  
  test "Serialize: 3rd chunk, same sid, length, typeid, and timestamp delta" do
    message = %TestMessage{data: <<152::size(100)-unit(8)>>}
    
    {serializer, _} = Serializer.new() |> Serializer.serialize(72, 50, message, 55)
    {serializer, _} = Serializer.serialize(serializer, 82, 50, message, 55)
    {_, binary} = Serializer.serialize(serializer, 92, 50, message, 55)
    
    expected_binary = <<0::2, 50::6, 152::size(100)-unit(8)>>
                            
    assert expected_binary == binary
  end
end