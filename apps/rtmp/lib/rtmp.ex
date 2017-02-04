defmodule Rtmp do

  @type connection_id :: String.t
  @type system_time_ms :: integer
  @type app_name :: String.t
  @type stream_key :: String.t

  @type deserialized_message :: Rtmp.Protocol.Messages.VideoData.t |
                                Rtmp.Protocol.Messages.AudioData.t |
                                Rtmp.Protocol.Messages.Abort.t |
                                Rtmp.Protocol.Messages.Acknowledgement.t |
                                Rtmp.Protocol.Messages.Amf0Command.t |
                                Rtmp.Protocol.Messages.Amf0Data.t |
                                Rtmp.Protocol.Messages.SetChunkSize.t |
                                Rtmp.Protocol.Messages.SetPeerBandwidth.t |
                                Rtmp.Protocol.Messages.UserControl.t |
                                Rtmp.Protocol.Messages.WindowAcknowledgementSize.t

  defmodule Behaviours do
    @moduledoc false

    defmodule ProtocolHandler do
      @moduledoc "Behaviour for modules that can serialize and deserialize RTMP messages"

      @type protocol_handler_pid :: pid

      @callback notify_input(protocol_handler_pid, binary) :: :ok
      @callback send_message(protocol_handler_pid, Rtmp.Protocol.DetailedMessage.t) :: :ok
    end

    defmodule SessionHandler do
      @moduledoc "Behaviour for modules that can act as session handlers"

      @type session_handler_pid :: pid
      @type stream_id :: non_neg_integer
      @type forced_timestamp :: non_neg_integer | nil
      @type io_count_direction :: :bytes_received | :bytes_sent

      @callback handle_rtmp_input(session_handler_pid, Rtmp.Protocol.DetailedMessage.t) :: :ok
      @callback notify_byte_count(session_handler_pid, io_count_direction, non_neg_integer) :: :ok
    end

    defmodule EventReceiver do
      @moduledoc "Behaviour for modules receiving session events"

      @type event_receiver_pid :: pid
      @type event :: any

      @callback send_event(event_receiver_pid, event) :: :ok
    end
  end
  
end