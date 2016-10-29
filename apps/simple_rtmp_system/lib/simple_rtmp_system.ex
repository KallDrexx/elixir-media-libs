defmodule SimpleRtmpSystem do
  use Application
  require Logger

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    rtmp_options = get_rtmp_options();
    RtmpServer.start_app(rtmp_options)

    children = []
    
    opts = [strategy: :one_for_one, name: SimpleRtmpSystem.Supervisor]
    Supervisor.start_link(children, opts) 
  end

  defp get_rtmp_options() do
    options = []
    options = case Application.get_env(:simple_rtmp_system, :rtmp_port) do
      nil -> options
      value -> Keyword.put(options, :port, value)
    end

    options = case Application.get_env(:simple_rtmp_system, :rtmp_director_module) do
      nil -> options
      value -> Keyword.put(options, :director_module, value)
    end

    options
  end
end
