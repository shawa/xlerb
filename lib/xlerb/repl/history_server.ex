defmodule Xlerb.REPL.HistoryServer do
  defstruct entries: %{}, index: 0, history_file: nil

  defmodule Entry do
    defstruct [:id, :timestamp, :content]

    def to_string(%Entry{id: id, timestamp: timestamp, content: content}) do
      "#{id}\t#{timestamp}\t#{content}"
    end

    def from_string(line) do
      [id_str, timestamp, content] = String.split(line, "\t")

      id = String.to_integer(id_str)
      timestamp = String.to_integer(timestamp)
      content = content

      %Entry{id: id, timestamp: timestamp, content: content}
    end
  end

  use GenServer

  @default_history_file "~/.xlerb_history"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    history_file = Keyword.get(opts, :history_file, @default_history_file)
    path = Path.expand(history_file)

    rows = load_history(path)

    id =
      try do
        Enum.max_by(rows, & &1.id).id
      rescue
        Enum.EmptyError -> 0
      end

    entries = Map.new(rows, &{&1.id, &1})

    {:ok, %__MODULE__{entries: entries, index: id, history_file: path}}
  end

  def index do
    GenServer.call(__MODULE__, :index)
  end

  def get(id) do
    GenServer.call(__MODULE__, {:get, id})
  end

  def insert(content) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    GenServer.call(__MODULE__, {:insert, now, content})
  end

  def persist do
    GenServer.call(__MODULE__, :persist)
  end

  @impl true
  def handle_call(:index, _from, state) do
    {:reply, state.index, state}
  end

  @impl true
  def handle_call(:persist, _from, state) do
    lines = Enum.map(state.entries, fn {_id, entry} -> Entry.to_string(entry) end)

    File.touch!(state.history_file)
    File.write!(state.history_file, Enum.join(lines, "\n"))

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get, id}, _from, state) do
    wrapped_id = if id < 0, do: id + state.index, else: id
    entry = Map.get(state.entries, wrapped_id)
    {:reply, entry, state}
  end

  @impl true
  def handle_call({:insert, timestamp, content}, _from, state) do
    new_id = state.index + 1
    new_entry = %Entry{id: new_id, timestamp: timestamp, content: content}
    new_entries = Map.put(state.entries, new_id, new_entry)

    {:reply, new_id, %{state | entries: new_entries, index: new_id}}
  end

  defp load_history(history_file) do
    case File.read(history_file) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(&Entry.from_string/1)

      {:error, :enoent} ->
        []
    end
  end
end
