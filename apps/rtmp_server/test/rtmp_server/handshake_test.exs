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
  
  test "Invalid C0", %{socket: socket, transport: transport} do
    transport.set_mode(socket, :bad_c0)
    {:error, :bad_c0} = RtmpServer.Handshake.process(socket, transport)
  end
  
  test "C0 timeout", %{socket: socket, transport: transport} do
    transport.set_mode(socket, :c0_timeout)
    {:error, :timeout} = RtmpServer.Handshake.process(socket, transport)
  end
  
  test "C1 timeout", %{socket: socket, transport: transport} do
    transport.set_mode(socket, :c1_timeout)
    {:error, :timeout} = RtmpServer.Handshake.process(socket, transport)
  end
  
  test "C2 timeout", %{socket: socket, transport: transport} do
    transport.set_mode(socket, :c2_timeout)
    {:error, :timeout} = RtmpServer.Handshake.process(socket, transport)
  end
 
 test "S0 timeout", %{socket: socket, transport: transport} do
    transport.set_mode(socket, :s0_timeout)
    {:error, :timeout} = RtmpServer.Handshake.process(socket, transport)
  end
  
  test "S1 timeout", %{socket: socket, transport: transport} do
    transport.set_mode(socket, :s1_timeout)
    {:error, :timeout} = RtmpServer.Handshake.process(socket, transport)
  end
  
  test "S2 timeout", %{socket: socket, transport: transport} do
    transport.set_mode(socket, :s2_timeout)
    {:error, :timeout} = RtmpServer.Handshake.process(socket, transport)
  end
  
  test "Incorrect c2 time", %{socket: socket, transport: transport} do
    transport.set_mode(socket, :bad_c2_time)
    {:error, :bad_c2_time} = RtmpServer.Handshake.process(socket, transport)
  end
  
  test "Incorrect c2 random", %{socket: socket, transport: transport} do
    transport.set_mode(socket, :bad_c2_random)
    {:error, :bad_c2_random} = RtmpServer.Handshake.process(socket, transport)
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
    
    defp do_recv(_, state = %State{mode: :bad_c0, stage: :socket_accepted}) do
      new_state = %{state | stage: :c0_sent}
      {:ok, {<<999>>, new_state}}
    end
    
    defp do_recv(_, %State{mode: :c0_timeout, stage: :socket_accepted}) do
      {:error, :timeout}
    end
    
    defp do_recv(_, %State{mode: :c1_timeout, stage: :s1_received}) do
      {:error, :timeout}
    end
    
    defp do_recv(_, %State{mode: :c2_timeout, stage: :s2_received}) do
      {:error, :timeout}
    end
  
    defp do_recv(1, state = %State{stage: :socket_accepted}) do
      # server receiving c0
      new_state = %{state | stage: :c0_sent}
      {:ok, {<<3>>, new_state}}
    end
    
    defp do_recv(1536, state = %State{stage: :s1_received}) do
      # server receiving c1
      new_state = %{state | stage: :c1_sent, c1_time: 1, c1_random: <<55::1528 * 8>> }
      response = <<new_state.c1_time::4 * 8>> <> <<0::4 * 8>> <> new_state.c1_random
      {:ok, {response, new_state}}
    end
    
    defp do_recv(1536, state = %State{mode: :bad_c2_time, stage: :s2_received}) do
      # server receiving c2
      
      invalid_time = state.s1_time + 1
      
      new_state = %{state | stage: :c2_sent }
      response = <<invalid_time::4 * 8>> <> <<0::4 * 8>> <> <<new_state.s1_random::1528 * 8>>
      {:ok, {response, new_state}}
    end
    
    defp do_recv(1536, state = %State{mode: :bad_c2_random, stage: :s2_received}) do
      # server receiving c2
      
      <<byte0::8, rest::binary>> = <<state.s1_random::1528 * 8>>
      bad_byte = if byte0 == 1 do
                      0
                    else
                      1
                    end
                          
      bad_random = <<bad_byte::8>> <> rest
      
      new_state = %{state | stage: :c2_sent }
      response = <<new_state.s1_time::4 * 8>> <> <<0::4 * 8>> <> bad_random
      {:ok, {response, new_state}}
    end
    
    defp do_recv(1536, state = %State{stage: :s2_received}) do
      # server receiving c2
      new_state = %{state | stage: :c2_sent }
      response = <<new_state.s1_time::4 * 8>> <> <<0::4 * 8>> <> <<new_state.s1_random::1528 * 8>>
      {:ok, {response, new_state}}
    end
    
    defp do_send(_, %State{mode: :s0_timeout, stage: :c0_sent}) do
      {:error, :timeout}
    end
    
    defp do_send(_, %State{mode: :s1_timeout, stage: :s0_received}) do
      {:error, :timeout}
    end
    
    defp do_send(_, %State{mode: :s2_timeout, stage: :c1_sent}) do
      {:error, :timeout}
    end
    
    defp do_send(<<3>>, state = %State{stage: :c0_sent}) do
      # client receiving s0
      {:ok, %{state | stage: :s0_received}}    
    end
    
    defp do_send(s1, state = %State{stage: :s0_received}) do
      <<time1::4 * 8, time2::4 * 8, random::1528 * 8>> = s1
      ^time2 = 0
      
      {:ok, %{state | stage: :s1_received, s1_time: time1, s1_random: random}}    
    end
    
    defp do_send(s2, state = %State{stage: :c1_sent}) do
      <<time1::4 * 8, _::4 * 8, random::1528 * 8>> = s2
          
      ^time1 = state.c1_time
      <<^random::1528 * 8>> = state.c1_random
      {:ok, %{state | stage: :s2_received}}    
    end  
  end
end