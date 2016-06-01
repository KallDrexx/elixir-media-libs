defmodule RtmpCommon.Messages.Handler do
  @moduledoc "Handles Rtmp messages coming in from it's peer and prepares responses"
  
  require Logger
  alias RtmpCommon.Messages.Types, as: Types
  
  defmodule State do
    defstruct responses: [],
              bytes_received: 0,
              last_ack_performed_at: 0,
              self_chunk_size: 128,
              self_bandwidth: 2500000,
              self_window_ack_size: 1048576,
              peer_window_ack_size: 900000000,
              peer_chunk_size: 128,
              session_id: nil,
              active_stream_ids: [0]
  end
  
  @doc "Creates a new message handler"
  def new(session_id) do
    # New connections should have peer bandwidth and window ack 
    # size responses queued
    
    bandwith_response = %RtmpCommon.Messages.Response{
      stream_id: 0,
      force_uncompressed: true,
      message: %RtmpCommon.Messages.Types.SetPeerBandwidth{
        window_size: 2500000, # TODO: this should be configurable
        limit_type: :dynamic
      }
    }
    
    ack_size_response = %RtmpCommon.Messages.Response{
      stream_id: 0,
      force_uncompressed: true,
      message: %RtmpCommon.Messages.Types.WindowAcknowledgementSize{
        size: 1048576, #TODO: should be configurable
      }
    }
    
    chunk_size_response = %RtmpCommon.Messages.Response{
      stream_id: 0,
      force_uncompressed: true,
      message: %RtmpCommon.Messages.Types.SetChunkSize{
        size: 4096, # TODO: should be configurable
      }
    }
    
    stream_begin = %RtmpCommon.Messages.Response{
      stream_id: 0,
      force_uncompressed: true,
      message: %RtmpCommon.Messages.Types.UserControl{
        type: :stream_begin,
        stream_id: 0
      }
    }
    
    %State{
      session_id: session_id, 
      responses: [bandwith_response, ack_size_response, chunk_size_response, stream_begin]
    }
  end
  
  @doc "Gets any queued responses"
  def get_responses(state = %State{}) do
    responses = state.responses
    new_state = %{state | responses: []}
    {new_state, responses}
  end
  
  @doc "Notifies the handler how many bytes have been received so far"
  def set_bytes_received(state = %State{}, bytes_received) when is_number(bytes_received) do
    if bytes_received - state.last_ack_performed_at > state.peer_window_ack_size do
      %{state |
        responses: [
          %RtmpCommon.Messages.Response{
            stream_id: 0,
            message: %RtmpCommon.Messages.Types.Acknowledgement{sequence_number: bytes_received}
          } | state.responses
        ],
        last_ack_performed_at: bytes_received,
        bytes_received: bytes_received
      }
    else
      %{state | bytes_received: bytes_received}
    end
  end
  
  @doc "Retrieves the current maximum chunk size for the peer"
  def get_peer_chunk_size(%State{peer_chunk_size: chunk_size}) do
    chunk_size
  end
  
  @doc "Handles the specified message"
  def handle(state = %State{}, message) do
    do_handle(state, message)
  end
  
  defp do_handle(state, %RtmpCommon.Messages.Types.WindowAcknowledgementSize{size: size}) do
    %{state | peer_window_ack_size: size}
  end
  
  defp do_handle(state, %RtmpCommon.Messages.Types.SetChunkSize{size: size}) do
    %{state | peer_chunk_size: size}
  end
  
  defp do_handle(state, %Types.Amf0Command{command_name: "connect"}) do
    response = %RtmpCommon.Messages.Response{
      stream_id: 0,
      message: %Types.Amf0Command{
        command_name: "_result",
        transaction_id: 1,
        command_object: %RtmpCommon.Amf0.Object{
            type: :object,
            value: %{
              "fmsVer" => %RtmpCommon.Amf0.Object{type: :string, value: "FMS/3,0,1,123"},
              "capabilities" => %RtmpCommon.Amf0.Object{type: :number, value: 31}
            } 
          },
        additional_values: [
          %RtmpCommon.Amf0.Object{
            type: :object,
            value: %{
              "level" => %RtmpCommon.Amf0.Object{type: :string, value: "status"},
              "code" => %RtmpCommon.Amf0.Object{type: :string, value: "NetConnection.Connect.Success"},
              "description" => %RtmpCommon.Amf0.Object{type: :string, value: "Connection succeeded"},
              "objectEncoding" => %RtmpCommon.Amf0.Object{type: :number, value: 0}
            }
          }
        ]
      }
    }
    
    response2 = %RtmpCommon.Messages.Response{
      stream_id: 0,
      message: %Types.Amf0Command{
        command_name: "onBWDone",
        transaction_id: 0,
        command_object: %RtmpCommon.Amf0.Object{type: :null},
        additional_values: [
          %RtmpCommon.Amf0.Object{type: :number, value: 8192}
        ]
      }
    }
    
    %{state |
      responses: [response, response2 | state.responses] 
    }
  end
  
  defp do_handle(state, command = %Types.Amf0Command{command_name: "createStream"}) do
    next_stream_id = Enum.max(state.active_stream_ids) + 1
    
    response = %RtmpCommon.Messages.Response{
      stream_id: 0,
      message: %Types.Amf0Command{
        command_name: "_result",
        transaction_id: command.transaction_id,
        command_object: %RtmpCommon.Amf0.Object{type: :null},
        additional_values: [%RtmpCommon.Amf0.Object{type: :number, value: next_stream_id}]
      }
    }
    
    %{state | responses: [response | state.responses]}
  end
  
  defp do_handle(state, command = %Types.Amf0Command{command_name: "publish"}) do
    [amf0_stream_name, amf0_stream_type] = command.additional_values
    
    stream_name = amf0_stream_name.value
    "live" = amf0_stream_type.value
    
    response = %RtmpCommon.Messages.Response{
      stream_id: 0,
      message: %Types.Amf0Command{
        command_name: "onStatus",
        transaction_id: 0,
        command_object: %RtmpCommon.Amf0.Object{type: :null},
        additional_values: [
          %RtmpCommon.Amf0.Object{type: :object, value: %{
            "level" => %RtmpCommon.Amf0.Object{type: :string, value: "status"},
            "code" => %RtmpCommon.Amf0.Object{type: :string, value: "NetStream.Publish.Start"},
            "description" => %RtmpCommon.Amf0.Object{type: :string, value: "Stream '" <> stream_name <> "' is now published."}
          }}
        ]
      }
    }
    
    %{state | responses: [response | state.responses]}
  end
  
  defp do_handle(state, message) do
    Logger.warn "#{state.session_id}: No handler for message: #{inspect(message)}"
    
    state
  end
end