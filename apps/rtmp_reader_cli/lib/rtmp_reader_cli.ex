defmodule RtmpReaderCli do

  alias RtmpSession.ChunkIo, as: ChunkIo
  alias RtmpSession.RawMessage, as: RawMessage
  alias RtmpSession.DetailedMessage, as: DetailedMessage

  require Logger

  defmodule DisplayOptions do
    defstruct av_bytes_shown: 100
  end

  def main(args) do
    {options, _, _} = OptionParser.parse(args)

    file_path = Keyword.get(options, :file, :none)
    av_bytes_shown = Keyword.get(options, :av_bytes_shown, 100)
    binary = get_file_binary!(file_path)
    chunk_io = ChunkIo.new()

    IO.puts("Reading file '#{file_path}' (totalling #{byte_size(binary)} bytes)")
    IO.puts("RTMP messages will be displayed one at a time, enter will need to be called to proceed after each one")
    IO.puts("")

    display_options = %DisplayOptions{av_bytes_shown: av_bytes_shown}

    read_next_message(chunk_io, binary, 0, display_options)
  end

  defp get_file_binary!(file_path) do
    if file_path == :none do
      raise("no file specified")
    end

    case File.read(file_path) do
      {:error, reason} -> raise("Failed to open file: #{reason}")
      {:ok, binary} -> binary
    end

  end

  defp read_next_message(chunk_io, unparsed_binary, count_so_far, display_options) do
    {chunk_io, chunk_result} = ChunkIo.deserialize(chunk_io, unparsed_binary)
    case chunk_result do
      :incomplete ->
        IO.puts("No more data available")
        IO.puts("")

      :split_message ->
        read_next_message(chunk_io, <<>>, count_so_far, display_options)

      raw_message = %RawMessage{} ->
        IO.puts("Message ##{count_so_far}")
        chunk_io = case RawMessage.unpack(raw_message) do
          {:error, :unknown_message_type} ->
            IO.puts("Found message of type #{raw_message.message_type_id} but we have no known way to unpack it!")
            chunk_io

          {:ok, message = %DetailedMessage{content: %RtmpSession.Messages.SetChunkSize{}}} ->
            display_message_details(message, display_options)
            ChunkIo.set_receiving_max_chunk_size(chunk_io, message.content.size)

          {:ok, message} ->
            display_message_details(message, display_options)
            chunk_io
        end

        IO.puts("")
        _ = IO.gets("Press enter for next message.")
        read_next_message(chunk_io, <<>>, count_so_far + 1, display_options)
    end
  end

  defp display_message_details(message = %DetailedMessage{content: %RtmpSession.Messages.AudioData{}}, display_options) do
    IO.puts("Found message of type '#{message.content.__struct__}'")
    IO.puts("Timestamp: #{message.timestamp}")
    IO.puts("Stream Id: #{message.stream_id}")

    byte_count_to_show = display_options.av_bytes_shown
    {shown_bytes, suffix} = case message.content.data do
      <<bytes::binary-size(byte_count_to_show), _::binary>> -> {bytes, "..."}
      bytes -> {bytes, ""}
    end

    IO.puts("Content: #{Base.encode16(shown_bytes)}#{suffix}")
  end

  defp display_message_details(message = %DetailedMessage{content: %RtmpSession.Messages.VideoData{}}, display_options) do
    IO.puts("Found message of type '#{message.content.__struct__}'")
    IO.puts("Timestamp: #{message.timestamp}")
    IO.puts("Stream Id: #{message.stream_id}")

    byte_count_to_show = display_options.av_bytes_shown
    {shown_bytes, suffix} = case message.content.data do
      <<bytes::binary-size(byte_count_to_show), _::binary>> -> {bytes, "..."}
      bytes -> {bytes, ""}
    end

    IO.puts("Content: #{Base.encode16(shown_bytes)}#{suffix}")
  end

  defp display_message_details(message = %DetailedMessage{}, _display_options) do
    IO.puts("Found message of type '#{message.content.__struct__}'")
    IO.puts("Timestamp: #{message.timestamp}")
    IO.puts("Stream Id: #{message.stream_id}")
    IO.puts("Content: #{inspect(message.content)}")
  end

end
