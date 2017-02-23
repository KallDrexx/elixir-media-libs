defmodule SimpleRtmpPlayer do

  def main(args) do
    {host, port, app, key} = parse_args(args)
    connection_info = %GenRtmpClient.ConnectionInfo{
      host: host,
      port: port,
      app_name: app,
      connection_id: "test-player"
    }

    IO.puts("Host: #{connection_info.host}")
    IO.puts("Port: #{connection_info.port}")
    IO.puts("App: #{connection_info.app_name}")
    IO.puts("Stream Key: #{key}")

    {:ok, _client_pid} = GenRtmpClient.start_link(SimpleRtmpPlayer.Client, connection_info)
    loop()
  end

  defp parse_args([host, port, app, key]), do: {host, port, app, key}
  defp parse_args(_), do: raise("Invalid parameters passed in")

  defp loop() do
    receive do
      _arg -> :ok
    end

    loop()
  end
end
