defmodule Xlerb.REPL.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    children = [
      {Xlerb.REPL.HistoryServer, opts},
      {Xlerb.REPL.Server, opts},
      {Xlerb.REPL.ShellServer, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
