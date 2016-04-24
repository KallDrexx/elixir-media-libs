defmodule RtmpServer.Handler do
  
  def start_link(ref, socket, transport, opts) do
    pid = spawn_link(__MODULE__, :init, [ref, socket, transport, opts])
    {:ok, pid}
  end
  
  def init(ref, socket, transport, opts) do
    :ok = :ranch.accept_ack(ref)
    perform_handshake(socket, transport)
  end

  def echo_loop(socket, transport) do
    case transport.recv(socket, 0, 5000) do
      {:ok, data} ->
        transport.send(socket, data)
        __MODULE__.echo_loop(socket, transport)
        
      _ -> :ok = transport.close(socket)
    end
  end
 
  defp perform_handshake(socket, transport) do
    # Echo server to verify ranch setup
    echo_loop(socket, transport)
  end
  
end