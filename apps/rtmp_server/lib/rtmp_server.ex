defmodule RtmpServer do
  use Application
  
  def start(_type, _args) do
    import Supervisor.Spec, warn: false
       
    children = [
      worker(RtmpServer.Worker, [])
    ]
    
    opts = [strategy: :one_for_one, name: RtmpServer.Supervisor]
    Supervisor.start_link(children, opts)
  end  
end
