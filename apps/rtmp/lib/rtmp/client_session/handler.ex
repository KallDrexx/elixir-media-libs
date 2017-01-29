defmodule Rtmp.ClientSession.Handler do
  @moduledoc """
  This module controls the process that processes the busines logic
  of a client in an RTMP connection.

  When RTMP messages come in from the server, it either responds with 
  response messages or raises events to be handled by the event 
  receiver process.  This allows for consumers to be flexible in how
  they utilize the RTMP client.
  """

  require Logger
  use GenServer

  
end