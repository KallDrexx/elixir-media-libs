defmodule GenRtmpClient.ConnectionInfo do
  @type t :: %__MODULE__{
    host: String.t,
    port: pos_integer,
    app_name: Rtmp.app_name,
    connection_id: String.t
  }

  defstruct host: nil,
            port: nil,
            app_name: nil,
            connection_id: nil
end