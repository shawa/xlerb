defmodule Xlerb.REPL do
  def run do
    initial_stack = []

    :shell.start_interactive({:noshell, :raw})

    # Start history server first
    {:ok, _history_pid} = Xlerb.REPL.HistoryServer.start_link([])

    {:ok, repl_pid} = Xlerb.REPL.Server.start_link(stack: initial_stack)
    {:ok, shell_pid} = Xlerb.REPL.ShellServer.start_link(repl_server: repl_pid)

    loop(shell_pid)
  end

  def loop(shell_pid) do
    case IO.getn("", 1) do
      :eof ->
        Xlerb.REPL.ShellServer.recv_chr(shell_pid, :eof)

      chr ->
        Xlerb.REPL.ShellServer.recv_chr(shell_pid, chr)
        loop(shell_pid)
    end
  end
end
