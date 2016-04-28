defmodule BinaryTransportMock do
  @moduledoc """
  Mock that allows defining binary data that should be returned
  """
     
  def start_link(binary) do
    Agent.start_link(fn -> binary end)
  end
    
  def recv(agent, num_bytes, _timeout) do
    binary = Agent.get(agent, fn state -> state end)
    case do_recv(num_bytes, binary, <<>>) do
      {:error, reason} -> {:error, reason}
      {result, remaining_binary} ->
        Agent.update(agent, fn _ -> remaining_binary end)
        {:ok, result}
    end
  end
  
  defp do_recv(0, binary, acc), do: {acc, binary}
  defp do_recv(_, <<>>, _), do: {:error, :timeout}
  defp do_recv(num_bytes, binary, acc) do
    <<byte::8, rest::binary>> = binary
    do_recv(num_bytes - 1, rest, acc <> <<byte>>)
  end
  
  
end