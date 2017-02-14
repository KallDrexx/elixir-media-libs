defmodule Rtmp.ClientSession.Events do
  @moduledoc false

  @type t :: Rtmp.ClientSession.Events.ConnectionResponseReceived.t |
    Rtmp.ClientSession.Events.PublishResponseReceived.t |
    Rtmp.ClientSession.Events.PlayResponseReceived.t |
    Rtmp.ClientSession.Events.StreamMetaDataReceived.t |
    Rtmp.ClientSession.Events.AudioVideoDataReceived.t  

  defmodule ConnectionResponseReceived do
    @moduledoc """
    Indicates that the server has accepted or rejcted the connection request
    """

    @type t :: %__MODULE__{
      was_accepted: boolean,
      response_text: String.t
    }

    defstruct was_accepted: nil,
              response_text: nil
  end

  defmodule PlayResponseReceived do
    @moduledoc """
    Indicates that the server has accepted or rejected our request for playback
    of a stream key
    """

    @type t :: %__MODULE__{
      was_accepted: boolean,      
      response_text: String.t
    }

    defstruct was_accepted: nil,
              response_text: nil
  end

  defmodule PublishResponseReceived do
    @moduledoc """
    Indicates that the server has accepted or rejected our request for publishing
    on a specific stream key
    """

    @type t :: %__MODULE__{
      was_accepted: boolean,      
      response_text: String.t
    }

    defstruct was_accepted: nil,
              response_text: nil
  end

  defmodule StreamMetaDataReceived do
    @moduledoc """
    Indicates that the server is reporting a change in the incoming stream's metadata
    """

    @type t :: %__MODULE__{
      meta_data: Rtmp.StreamMetadata.t,
      stream_key: Rtmp.stream_key
    }

    defstruct meta_data: nil,
              stream_key: nil
  end

  defmodule AudioVideoDataReceived do
    @moduledoc """
    Indicates that audio or video data has been received
    """

    @type t :: %__MODULE__{
      stream_key: Rtmp.stream_key,
      data_type: :audio | :video,
      data: binary,
      timestamp: non_neg_integer,
      received_at_timestamp: pos_integer,
    }

    defstruct stream_key: nil,
              data_type: nil, 
              data: <<>>,
              timestamp: nil,
              received_at_timestamp: nil
  end
end