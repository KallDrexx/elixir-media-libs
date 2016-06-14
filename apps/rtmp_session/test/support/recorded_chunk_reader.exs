defmodule RecordedChunkReader do
  require Logger

  defmodule State do
    defstruct base_directory: nil,
              file_queue: []
  end

  def new(directory) do
    {:ok, files} = File.ls(directory)
    sorted_files = Enum.sort(files)

    %State{file_queue: files, base_directory: directory}
  end

  def read_next(state = %State{file_queue: []}) do
    {state, :done}
  end

  def read_next(state = %State{file_queue: [file | rest]}) do
    binary = File.read!(state.base_directory <> "/" <> file)
    new_state = %{state | file_queue: rest}

    {new_state, binary}
  end
end