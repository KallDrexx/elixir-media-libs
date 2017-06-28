defmodule Rtmp.IoTotals do
  @moduledoc """
  Contains totals for bytes and packets that have been sent,
  received, or dropped over the life of a RTMP connection.
  """

  @type t :: %__MODULE__{
    bytes_sent: non_neg_integer,
    bytes_received: non_neg_integer,
    bytes_dropped: non_neg_integer,
    packets_sent: non_neg_integer,
    packets_received: non_neg_integer,
    packets_dropped: non_neg_integer
  }

  defstruct bytes_sent: 0,
            bytes_received: 0,
            bytes_dropped: 0,
            packets_sent: 0,
            packets_received: 0,
            packets_dropped: 0
  
end