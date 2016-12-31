defmodule Rtmp.ServerSession.Events do

  @type t :: Rtmp.ServerSession.Events.PeerChunkSizeChanged.t |
    Rtmp.ServerSession.Events.SelfChunkSizeChanged.t |
    Rtmp.ServerSession.Events.ConnectionRequested.t |
    Rtmp.ServerSession.Events.ReleaseStreamRequested.t |
    Rtmp.ServerSession.Events.PublishStreamRequested.t |
    Rtmp.ServerSession.Events.StreamMetaDataChanged.t |
    Rtmp.ServerSession.Events.AudioVideoDataReceived.t |
    Rtmp.ServerSession.Events.UnhandleableAmf0Command.t |
    Rtmp.ServerSession.Events.PublishingFinished.t |
    Rtmp.ServerSession.Events.PlayStreamRequested.t |
    Rtmp.ServerSession.Events.PlayStreamFinished.t

  defmodule PeerChunkSizeChanged do
    @type t :: %__MODULE__{
      new_chunk_size: pos_integer()
    }

    defstruct new_chunk_size: nil
  end

  defmodule SelfChunkSizeChanged do
    @type t :: %__MODULE__{
      new_chunk_size: pos_integer()
    }

    defstruct new_chunk_size: nil
  end

  defmodule ConnectionRequested do
    @type t :: %__MODULE__{
      request_id: integer(),
      app_name: Rtmp.app_name
    }

    defstruct request_id: nil,
              app_name: nil
  end

  defmodule ReleaseStreamRequested do
    @type t :: %__MODULE__{
      request_id: integer(),
      app_name: Rtmp.app_name,
      stream_key: Rtmp.stream_key
    }

    defstruct request_id: nil,
              app_name: nil,
              stream_key: nil
  end

  defmodule PublishStreamRequested do
    @type t :: %__MODULE__{
      request_id: integer(),
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
    @type t :: %__MODULE__{
      app_name: Rtmp.app_name,
      stream_key: Rtmp.stream_key
    }

    defstruct app_name: nil,
              stream_key: nil
  end

  defmodule StreamMetaDataChanged do
    @type t :: %__MODULE__{
      app_name: Rtmp.app_name,
      stream_key: Rtmp.stream_key,
      meta_data: Rtmp.ServerSession.StreamMetadata.t
    }

    defstruct app_name: nil,
              stream_key: nil,
              meta_data: nil
  end

  defmodule AudioVideoDataReceived do
    @type t :: %__MODULE__{
      app_name: Rtmp.app_name,
      stream_key: Rtmp.stream_key,
      data_type: :audio | :video,
      data: <<>>,
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
    @type t :: %__MODULE__{
      command: %Rtmp.Protocol.Messages.Amf0Command{}
    }

    defstruct command: nil
  end

  defmodule PlayStreamRequested do
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
    @type t :: %__MODULE__{
      app_name: Rtmp.app_name,
      stream_key: Rtmp.stream_key
    }

    defstruct app_name: nil,
              stream_key: nil
  end

end