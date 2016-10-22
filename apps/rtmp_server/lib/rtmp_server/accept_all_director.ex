defmodule RtmpServer.AcceptAllDirector do
  @behaviour RtmpServer.Director

  def handle_request(_session_id, _event = %RtmpSession.Events.ConnectionRequested{}) do
    :accepted
  end

  def handle_request(_session_id, _event = %RtmpSession.Events.PublishStreamRequested{}) do
    :accepted
  end

  def handle_request(_session_id, _event = %RtmpSession.Events.ReleaseStreamRequested{}) do
    :accepted
  end

  def handle_notification(_session_id, _event = %RtmpSession.Events.StreamMetaDataChanged{}) do
    :ok
  end

  def handle_notification(_session_id, _event = %RtmpSession.Events.AudioVideoDataReceived{}) do
    :ok
  end
end