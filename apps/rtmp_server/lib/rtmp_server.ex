defmodule RtmpServer do
  use Application
  require Logger

  @type session_id :: String.t
  
  def start(_type, args) do
    import Supervisor.Spec, warn: false

    rtmp_options = Keyword.take(args, [:port, :fms_version, :chunk_size])

    children = [
      worker(RtmpServer.Worker, [rtmp_options])
    ]
    
    opts = [strategy: :one_for_one, name: RtmpServer.Supervisor]
    Supervisor.start_link(children, opts)
  end
  
  def recompile() do
    Mix.Task.reenable("app.start")
    Mix.Task.reenable("compile")
    Mix.Task.reenable("compile.all")
    compilers = Mix.compilers
    Enum.each compilers, &Mix.Task.reenable("compile.#{&1}")
    Mix.Task.run("compile.all")
  end  
end
