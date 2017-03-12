defmodule SimpleRtmpProxy do

  def main(args) do
    import Supervisor.Spec, warn: false

    {in_port, host, out_port, app} = parse_args(args)
    in_port = String.to_integer(in_port)
    out_port = String.to_integer(out_port)

    children = [worker(SimpleRtmpProxy.ServerWorker, [in_port, host, out_port, app])]
    opts = [strategy: :one_for_one, name: SimpleRtmpProxy.Supervisor]
    Supervisor.start_link(children, opts)

    Process.sleep(:infinity)
  end
  
  defp parse_args([in_port, host, out_port, app]), do: {in_port, host, out_port, app}
  defp parse_args(_), do: raise("Expected parameters: input_port output_host output_port output_app")
end
