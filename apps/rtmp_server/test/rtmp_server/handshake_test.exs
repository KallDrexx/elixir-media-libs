defmodule RtmpServer.HandshakeTest do
  use ExUnit.Case, async: true
  
  test "abc" do
    transport = RtmpServer.TestUtils.TestTransport.blank
    
    assert 1 == 1
  end
end

defmodule RtmpServer.TestUtils.TestTransport do
 
  def blank do
    :ok
  end
end