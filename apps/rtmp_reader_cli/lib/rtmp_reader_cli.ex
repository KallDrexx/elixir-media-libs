defmodule RtmpReaderCli do

  alias RtmpSession.ChunkIo, as: ChunkIo
  alias RtmpSession.RawMessage, as: RawMessage
  alias RtmpSession.DetailedMessage, as: DetailedMessage

  def main(args) do
    {options, _, _} = OptionParser.parse(args)

    file_path = Keyword.get(options, :file, :none)
    binary = get_file_binary!(file_path)
    chunk_io = ChunkIo.new()

    IO.puts("Reading file '#{file_path}' (totalling #{byte_size(binary)} bytes)")
    IO.puts("RTMP messages will be displayed one at a time, enter will need to be called to proceed after each one")
    IO.puts("")

    read_next_message(chunk_io, binary, 0)
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

  defp read_next_message(chunk_io, unparsed_binary, count_so_far) do
    {chunk_io, chunk_result} = ChunkIo.deserialize(chunk_io, unparsed_binary)
    case chunk_result do
      :incomplete ->
        IO.puts("No more data available")
        IO.puts("")

      :split_message ->
        read_next_message(chunk_io, <<>>, count_so_far)

      raw_message = %RawMessage{} ->
        IO.puts("Message ##{count_so_far}")
        chunk_io = case RawMessage.unpack(raw_message) do
          {:error, :unknown_message_type} ->
            IO.puts("Found message of type #{raw_message.message_type_id} but we have no known way to unpack it!")
            chunk_io

          {:ok, message = %DetailedMessage{content: %RtmpSession.Messages.SetChunkSize{}}} ->
            display_message_details(message)
            ChunkIo.set_receiving_max_chunk_size(chunk_io, message.content.size)

          {:ok, message} ->
            display_message_details(message)
            chunk_io
        end

        IO.puts("")
        IO.gets("Press enter for next message.")
        read_next_message(chunk_io, <<>>, count_so_far + 1)
    end
  end

  defp display_message_details(message = %DetailedMessage{}) do
    IO.puts("Found message of type '#{message.content.__struct__}'")
    IO.puts("Timestamp: #{message.timestamp}")
    IO.puts("Stream Id: #{message.stream_id}")
    IO.puts("Content: #{inspect(message.content)}")
  end

end
