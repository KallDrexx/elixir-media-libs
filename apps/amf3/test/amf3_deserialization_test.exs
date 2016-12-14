defmodule Amf3DeserializationTest do
  use ExUnit.Case, async: true

  test "Undefined marker deserializes to nil" do
    binary = <<0x00>>

    assert [nil] == Amf3.deserialize(binary)
  end

  test "Null marker deserializes to nil" do
    binary = <<0x01>>

    assert [nil] == Amf3.deserialize(binary)
  end

  test "False marker deserializes to false" do
    binary = <<0x02>>

    assert [false] == Amf3.deserialize(binary)
  end

  test "True marker deserializes to true" do
    binary = <<0x03>>

    assert [true] == Amf3.deserialize(binary)
  end

  test "Integer marker with value below 128 deserializes to number" do
    binary = <<0x04, 0x7f>>

    assert [127] == Amf3.deserialize(binary)
  end

  test "Integer marker with value below 65408 deserializes to number" do
    binary = <<0x04, 0xff, 0x7f>>

    assert [65407] == Amf3.deserialize(binary)
  end

  test "Integer marker with value below 16777088 deserializes to number" do
    binary = <<0x04, 0xff, 0xff, 0x7f>>

    assert [16777087] == Amf3.deserialize(binary)
  end

  test "Integer marker with value below 2155905152 deserializes to number" do
    binary = <<0x04, 0xff, 0xff, 0xff, 0xff>>

    assert [4294967295] == Amf3.deserialize(binary)
  end

  test "Double marker with value deserializes to number" do
    binary = <<0x05, 532.5::float-64>>

    assert [532.5] == Amf3.deserialize(binary)
  end
  
end