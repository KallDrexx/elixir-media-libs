defmodule RtmpCommon.RtmpTime do
  @moduledoc """  
  Provides utilities to work with timestamps in an RTMP context.
  
  RTMP timestamps are 32 bits (unsigned) integers and thus roll over every ~50 days.
  All adjacent timestamps are within 2^31 - 1 milliseconds of 
  each other (e.g.  10000 comes after 4000000000, and 3000000000 comes before 4000000000).
  
  """
  
  @max_timestamp :math.pow(2, 32)
  @adjacent_threshold :math.pow(2, 31) - 1
  
  @doc """
  Applies the specified delta to a timestamp
  
  ## Examples
  
    iex> RtmpCommon.RtmpTime.apply_delta(1000, 500)
    1500
    
    iex> RtmpCommon.RtmpTime.apply_delta(1000, -500)
    500
    
    iex> RtmpCommon.RtmpTime.apply_delta(1000, -2000)
    4294966296
    
    iex> RtmpCommon.RtmpTime.apply_delta(4294966296, 2000)
    1000
  """
  def apply_delta(timestamp, delta) do
    new_timestamp = timestamp + delta
    cond do
      new_timestamp < 0 -> @max_timestamp + new_timestamp |> trunc
      new_timestamp > @max_timestamp -> new_timestamp - @max_timestamp |> trunc
      true -> new_timestamp |> trunc
    end
  end
  
  
  @doc """
  Gets the delta between an old RTMP timestamp and a new RTMP timestamp
  
  ## Examples
    
    iex> RtmpCommon.RtmpTime.get_delta(4000000000, 4000001000)
    1000
    
    iex> RtmpCommon.RtmpTime.get_delta(4000000000, 10000)
    294977296
    
    iex> RtmpCommon.RtmpTime.get_delta(4000000000, 3000000000)
    -1000000000
  
  """
  def get_delta(previous_timestamp, new_timestamp) do
    difference = new_timestamp - previous_timestamp
    is_adjacent = if :erlang.abs(difference) <= @adjacent_threshold, do: true, else: false
    
    do_get_delta(previous_timestamp, new_timestamp, is_adjacent)
    |> trunc
  end
  
  defp do_get_delta(timestamp1, timestamp2, true) do
    timestamp2 - timestamp1
  end
  
  defp do_get_delta(timestamp1, timestamp2, false) when timestamp1 > timestamp2 do
    (@max_timestamp - timestamp1) + timestamp2
  end
  
  defp do_get_delta(timestamp1, timestamp2, false) do
    (@max_timestamp - timestamp2) + timestamp1
  end
end