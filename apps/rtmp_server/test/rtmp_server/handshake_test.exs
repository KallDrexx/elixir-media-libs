defmodule RtmpServer.HandshakeTest do
  use ExUnit.Case, async: true
  
  setup do
    transport = __MODULE__.HandshakeClient
    {:ok, pid} = transport.start_link    
    {:ok, socket: pid, transport: transport}
  end
  
  test "Valid Rtmp Handshake", %{socket: socket, transport: transport} do
    :ok = RtmpServer.Handshake.process(socket, transport)
  end
  
  defmodule HandshakeClient do
    defmodule State do
      defstruct mode: :valid_client,
                stage: :socket_accepted,
                s1_time: 0,
                c1_time: 0,
                s1_random: <<>>,
                c1_random: <<>>
    end
    
    def start_link do
      Agent.start_link fn -> %State{} end
    end
    
    def set_mode(agent, mode) do
      current_state = Agent.get(agent, fn state -> state end)
      new_state = %{current_state | mode: mode}
      Agent.update(agent, fn _ -> new_state end)
    end
    
    def recv(agent, num_bytes, _) do
      current_state = Agent.get(agent, fn state -> state end)
      case do_recv(num_bytes, current_state) do
        {:ok, {response, new_state}} ->
          Agent.update(agent, fn _ -> new_state end)
          {:ok, response}
          
        {:error, reason} -> {:error, reason}
      end
    end
    
    def send(agent, bytes_sent) do
      current_state = Agent.get(agent, fn state -> state end)
      
      case do_send(bytes_sent, current_state) do
        {:ok, new_state} -> Agent.update(agent, fn _ -> new_state end)
        {:error, reason} -> {:error, reason}        
      end
    end
  
    defp do_recv(1, state = %State{mode: :valid_client, stage: :socket_accepted}) do
      # server receiving c0
      new_state = %{state | stage: :c0_sent}
      {:ok, {<<3>>, new_state}}
    end
    
    defp do_recv(1536, state = %State{mode: :valid_client, stage: :s1_received}) do
      # server receiving c1
      new_state = %{state | stage: :c1_sent, c1_time: 1, c1_random: <<55::1528 * 8>> }
      response = <<new_state.c1_time::4 * 8>> <> <<0::4 * 8>> <> new_state.c1_random
      {:ok, {response, new_state}}
    end
    
    defp do_recv(1536, state = %State{mode: :valid_client, stage: :s2_received}) do
      # server receiving c2
      new_state = %{state | stage: :c2_sent }
      response = <<new_state.s1_time::4 * 8>> <> <<0::4 * 8>> <> <<new_state.s1_random::1528 * 8>>
      {:ok, {response, new_state}}
    end
    
    defp do_send(<<3>>, state = %State{mode: :valid_client, stage: :c0_sent}) do
      # client receiving s0
      {:ok, %{state | stage: :s0_received}}    
    end
    
    defp do_send(s1, state = %State{mode: :valid_client, stage: :s0_received}) do
      <<time1::4 * 8, time2::4 * 8, random::1528 * 8>> = s1
      ^time2 = 0
      
      {:ok, %{state | stage: :s1_received, s1_time: time1, s1_random: random}}    
    end
    
    defp do_send(s2, state = %State{mode: :valid_client, stage: :c1_sent}) do
      <<time1::4 * 8, _::4 * 8, random::1528 * 8>> = s2
          
      ^time1 = state.c1_time
      <<^random::1528 * 8>> = state.c1_random
      {:ok, %{state | stage: :s2_received}}    
    end  
  end
end