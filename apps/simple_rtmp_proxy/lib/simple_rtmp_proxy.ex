defmodule SimpleRtmpProxy do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(SimpleRtmpProxy.Worker, [])
    ]

    opts = [strategy: :one_for_one, name: SimpleRtmpProxy.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
