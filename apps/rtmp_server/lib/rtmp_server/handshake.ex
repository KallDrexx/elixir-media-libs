defmodule RtmpServer.Handshake do 
  require Logger
  
  @doc "Processes a handshake for a new rtmp connection"
  @spec process(port(), any()) :: :ok | {:error, any()}
  def process(socket, transport) do
      with :ok <- receive_c0(socket, transport),
           :ok <- send_s0(socket, transport),
           {:ok, sent_details} <- send_s1(socket, transport),
           {:ok, received_details} <- receive_c1(socket, transport),
           :ok <- send_s2(socket, transport, received_details),
           do: receive_c2(socket, transport, sent_details)
  end
  
  defp receive_c0(socket, transport) do
    case transport.recv(socket, 1, 5000) do
      {:ok, byte} -> validate_c0(byte)
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp validate_c0(byte) when byte < <<32>>, do: :ok
  defp validate_c0(_), do: {:error, :bad_c0}
  
  defp receive_c1(socket, transport) do
    case transport.recv(socket, 1536, 5000) do
      {:ok, bytes} -> transform_c1(bytes)
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp transform_c1(bytes) do
    <<time::8 * 4, _zeros::8 * 4, random::binary-size(1528)>> = bytes
    {:ok, %RtmpServer.Handshake.Details{time: time, random_data: random}}
  end
  
  defp receive_c2(socket, transport, sent_details) do
    case transport.recv(socket, 1536, 5000) do
      {:ok, bytes} -> validate_c2(bytes, sent_details)
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp validate_c2(bytes, sent_details) do
    <<time1::8 * 4, _time2::8 * 4, random_echo::binary-size(1528)>> = bytes
    
    cond do
      time1 != sent_details.time -> {:error, :bad_c2_time}
      random_echo != sent_details.random_data -> {:error, :bad_c2_random}      
      true -> :ok      
    end
  end
  
  defp send_s0(socket, transport) do
    case transport.send(socket, <<3>>) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp send_s1(socket, transport) do
    time = 0
    zeros = <<0::8 * 4>>
    random = generate_random_binary(1528, <<>>)
    
    case transport.send(socket, <<time::8 * 4>> <> zeros <> random) do
      :ok -> {:ok, %RtmpServer.Handshake.Details{time: time, random_data: random}}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp send_s2(socket, transport, received_details) do
    time1 = <<received_details.time::8 * 4>>
    time2 = <<0::8 * 4>>
    random = received_details.random_data
    
    case transport.send(socket, time1 <> time2 <> random) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp generate_random_binary(0, accumulator), do: accumulator
  defp generate_random_binary(count, accumulator), do: generate_random_binary(count - 1,  accumulator <> <<:random.uniform(254)>> )
  
end