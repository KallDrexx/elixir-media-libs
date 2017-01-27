defmodule Rtmp.ServerSession.Events do
  @moduledoc false

  @type t :: Rtmp.ServerSession.Events.PeerChunkSizeChanged.t |
    Rtmp.ServerSession.Events.ConnectionRequested.t |
    Rtmp.ServerSession.Events.ReleaseStreamRequested.t |
    Rtmp.ServerSession.Events.PublishStreamRequested.t |
    Rtmp.ServerSession.Events.StreamMetaDataChanged.t |
    Rtmp.ServerSession.Events.AudioVideoDataReceived.t |
    Rtmp.ServerSession.Events.UnhandleableAmf0Command.t |
    Rtmp.ServerSession.Events.PublishingFinished.t |
    Rtmp.ServerSession.Events.PlayStreamRequested.t |
    Rtmp.ServerSession.Events.PlayStreamFinished.t |
    Rtmp.ServerSession.Events.NewByteIOTotals.t |
    Rtmp.ServerSession.Events.AcknowledgementReceived.t |
    Rtmp.ServerSession.Events.PingResponseReceived.t |
    Rtmp.ServerSession.Events.PingRequestSent.t

  defmodule PeerChunkSizeChanged do
    @moduledoc """
    Event indicating that the peer is changing the maximum size of the 
    RTMP chunks they will be sending
    """

    @type t :: %__MODULE__{
      new_chunk_size: pos_integer
    }

    defstruct new_chunk_size: nil
  end

  defmodule ConnectionRequested do
    @moduledoc """
    Event indicating that the peer is requesting a ConnectionRequested
    on the specified application name
    """

    @type t :: %__MODULE__{
      request_id: integer,
      app_name: Rtmp.app_name
    }

    defstruct request_id: nil,
              app_name: nil
  end

  defmodule ReleaseStreamRequested do
    @moduledoc """
    Event indicating that the peer is requesting a stream key
    be released for use.
    """

    @type t :: %__MODULE__{
      request_id: integer,
      app_name: Rtmp.app_name,
      stream_key: Rtmp.stream_key
    }

    defstruct request_id: nil,
              app_name: nil,
              stream_key: nil
  end

  defmodule PublishStreamRequested do
    @moduledoc """
    Event indicating that the peer is requesting the ability to 
    publish on the specified stream key.
    """

    @type t :: %__MODULE__{
      request_id: integer,
      app_name: Rtmp.app_name,
      stream_key: Rtmp.stream_key,
      stream_id: non_neg_integer
    }

    defstruct request_id: nil,
              app_name: nil,
              stream_key: nil,
              stream_id: nil
  end

  defmodule PublishingFinished do
    @moduledoc """
    Event indicating that the peer is finished publishing on the
    specified stream key.
    """

    @type t :: %__MODULE__{
      app_name: Rtmp.app_name,
      stream_key: Rtmp.stream_key
    }

    defstruct app_name: nil,
              stream_key: nil
  end

  defmodule StreamMetaDataChanged do
    @moduledoc """
    Event indicating that the peer is changing metadata properties 
    of the stream being published.
    """

    @type t :: %__MODULE__{
      app_name: Rtmp.app_name,
      stream_key: Rtmp.stream_key,
      meta_data: Rtmp.StreamMetadata.t
    }

    defstruct app_name: nil,
              stream_key: nil,
              meta_data: nil
  end

  defmodule AudioVideoDataReceived do
    @moduledoc """
    Event indicating that audio or video data was received.
    """

    @type t :: %__MODULE__{
      app_name: Rtmp.app_name,
      stream_key: Rtmp.stream_key,
      data_type: :audio | :video,
      data: binary,
      timestamp: non_neg_integer,
      received_at_timestamp: pos_integer
    }

    defstruct app_name: nil,
              stream_key: nil,
              data_type: nil, 
              data: <<>>,
              timestamp: nil,
              received_at_timestamp: nil
  end

  defmodule UnhandleableAmf0Command do
    @moduledoc """
    Event indicating that an Amf0 command was received that was not able
    to be handled.
    """

    @type t :: %__MODULE__{
      command: %Rtmp.Protocol.Messages.Amf0Command{}
    }

    defstruct command: nil
  end

  defmodule PlayStreamRequested do
    @moduledoc """
    Event indicating that the peer is requesting playback of the specified stream.
    """

    @type video_type :: :live | :recorded | :any

    @type t :: %__MODULE__{
      request_id: integer,
      app_name: Rtmp.app_name,
      stream_key: Rtmp.stream_key,
      video_type: video_type,
      start_at: non_neg_integer,
      duration: integer,
      reset: boolean,
      stream_id: non_neg_integer
    }

    defstruct request_id: nil,
              app_name: nil,
              stream_key: nil,
              video_type: nil,
              start_at: nil,
              duration: nil,
              reset: nil,
              stream_id: nil
  end

  defmodule PlayStreamFinished do
    @moduledoc """
    Event indicating that they are finished with playback of the specified stream.
    """

    @type t :: %__MODULE__{
      app_name: Rtmp.app_name,
      stream_key: Rtmp.stream_key
    }

    defstruct app_name: nil,
              stream_key: nil
  end

  defmodule NewByteIOTotals do
    @moduledoc """
    Event indicating the total number of bytes sent or received from the client has
    changed in value
    """

    @type t :: %__MODULE__{
      bytes_sent: non_neg_integer,
      bytes_received: non_neg_integer
    }

    defstruct bytes_received: 0,
              bytes_sent: 0
  end

  defmodule AcknowledgementReceived do
    @moduledoc """
    Event indicating that the client has sent an acknowledgement that they have received
    the specified number of bytes
    """

    @type t :: %__MODULE__{
      bytes_received: non_neg_integer
    }

    defstruct bytes_received: 0
  end

  defmodule PingRequestSent do
    @moduledoc """
    Event indicating that the server has sent a ping request to the client
    """

    @type t :: %__MODULE__{
      timestamp: non_neg_integer
    }

    defstruct timestamp: nil
  end

  defmodule PingResponseReceived do
    @moduledoc """
    Event indicating that the client has responded to a ping request
    """

    @type t :: %__MODULE__{
      timestamp: non_neg_integer
    }

    defstruct timestamp: nil
  end

end