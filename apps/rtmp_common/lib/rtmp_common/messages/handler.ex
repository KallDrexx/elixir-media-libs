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
              session_id: nil,
              stage: :waiting_for_connection
  end
  
  @doc "Creates a new message handler"
  def new(session_id) do
    # New connections should have peer bandwidth and window ack 
    # size responses queued
    
    bandwith_response = %RtmpCommon.Messages.Response{
      stream_id: 0,
      message: %RtmpCommon.Messages.Types.SetPeerBandwidth{
        window_size: 2500000, # TODO: this should be configurable
        limit_type: :dynamic
      }
    }
    
    ack_size_response = %RtmpCommon.Messages.Response{
      stream_id: 0,
      message: %RtmpCommon.Messages.Types.WindowAcknowledgementSize{
        size: 1048576, #TODO: should be configurable
      }
    }
    
    %State{session_id: session_id, responses: [bandwith_response, ack_size_response]}
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
  
  @doc "Handles the specified message"
  def handle(state = %State{}, message) do
    do_handle(state, message)
  end
  
  defp do_handle(state, %RtmpCommon.Messages.Types.WindowAcknowledgementSize{size: size}) do
    %{state | peer_window_ack_size: size}
  end
  
  defp do_handle(state = %State{stage: :waiting_for_connection}, %Types.Amf0Command{command_name: "connect"}) do
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
    
    %{state |
      stage: :connected,
      responses: [response | state.responses] 
    }
  end
  
  defp do_handle(state, message) do
    Logger.error "#{state.session_id}: No handler for message: #{inspect(message)}"
    
    state
  end
end