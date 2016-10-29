defmodule RtmpServer do
  use Application
  require Logger

  @type session_id :: String.t
  
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    arguments = [
      port: Application.get_env(:rtmp_server, :port, 1935),
      fms_version: Application.get_env(:rtmp_server, :fms_version, "FMS/3,0,0,1233"),
      chunk_size: Application.get_env(:rtmp_server, :chunk_size, 4096),
      director_module: Application.get_env(:rtmp_server, :director_module, nil)
    ]

    children = [
      worker(RtmpServer.Worker, [arguments])
    ]
    
    opts = [strategy: :one_for_one, name: RtmpServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @spec start_app([]) :: {:ok, [atom()]} | {:error, {atom(), term}}
  def start_app(arguments) do
    :ok = register_arguments(arguments)

    Application.ensure_all_started(:rtmp_server)
  end

  defp register_arguments([]) do
    :ok
  end

  defp register_arguments([{:port, port} | tail]) do
    Application.put_env(:rtmp_server, :port, port, persistent: true)
    register_arguments(tail)
  end

  defp register_arguments([{:fms_version, fms_version} | tail]) do
    Application.put_env(:rtmp_server, :fms_version, fms_version, persistent: true)
    register_arguments(tail)
  end

  defp register_arguments([{:chunk_size, chunk_size} | tail]) do
    Application.put_env(:rtmp_server, :chunk_size, chunk_size, persistent: true)
    register_arguments(tail)
  end

  defp register_arguments([{:director_module, director_module} | tail]) do
    Application.put_env(:rtmp_server, :director_module, director_module, persistent: true)
    register_arguments(tail)
  end

  defp register_arguments([{key, value} | tail]) do
    Logger.warn "Attempted to start rtmp server app with unknown options " <>
      "{#{inspect(key)}, #{inspect(value)}}" 
  end
end
