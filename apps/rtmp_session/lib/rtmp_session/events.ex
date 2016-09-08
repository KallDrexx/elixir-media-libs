defmodule RtmpSession.Events do

  @type t :: RtmpSession.Events.PeerChunkSizeChanged.t |
    RtmpSession.Events.SelfChunkSizeChanged.t |
    RtmpSession.Events.ConnectionRequested.t |
    RtmpSession.Events.ReleaseStreamRequested.t |
    RtmpSession.Events.PublishStreamRequested.t |
    RtmpSession.Events.StreamMetaDataChanged.t |
    RtmpSession.Events.AudioVideoDataReceived.t |
    RtmpSession.Events.UnhandleableAmf0Command.t

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
      app_name: String.t
    }

    defstruct request_id: nil,
              app_name: nil
  end

  defmodule ReleaseStreamRequested do
    @type t :: %__MODULE__{
      request_id: integer(),
      app_name: String.t,
      stream_key: String.t
    }

    defstruct request_id: nil,
              app_name: nil,
              stream_key: nil
  end

  defmodule PublishStreamRequested do
    @type t :: %__MODULE__{
      request_id: integer(),
      app_name: String.t,
      stream_key: String.t
    }

    defstruct request_id: nil,
              app_name: nil,
              stream_key: nil
  end

  defmodule StreamMetaDataChanged do
    @type t :: %__MODULE__{
      app_name: String.t,
      stream_key: String.t,
      meta_data: RtmpSession.StreamMetadata.t
    }

    defstruct app_name: nil,
              stream_key: nil,
              meta_data: nil
  end

  defmodule AudioVideoDataReceived do
    @type t :: %__MODULE__{
      app_name: String.t,
      stream_key: String.t,
      data_type: :audio | :video,
      data: <<>>
    }

    defstruct app_name: nil,
              stream_key: nil,
              data_type: nil, 
              data: <<>>
  end

  defmodule UnhandleableAmf0Command do
    @type t :: %__MODULE__{
      command: %RtmpSession.Messages.Amf0Command{}
    }

    defstruct command: nil
  end

end