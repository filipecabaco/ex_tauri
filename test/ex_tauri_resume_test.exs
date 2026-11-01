defmodule ExTauri.ResumeTest do
  use ExUnit.Case, async: false

  alias ExTauri.Resume

  # A resume logs, and the callback that raises is logged too.
  @moduletag :capture_log

  describe "suspended/4" do
    test "a tick on time, or a little late, is not a resume" do
      assert Resume.suspended(0, 2_000, 2_000, 5_000) == :awake
      assert Resume.suspended(0, 6_000, 2_000, 5_000) == :awake
      assert Resume.suspended(0, 7_000, 2_000, 5_000) == :awake
    end

    test "a tick later than `late` is, with how long the app was away" do
      assert Resume.suspended(0, 7_001, 2_000, 5_000) == {:suspended, 5_001}
      assert Resume.suspended(1_000, 63_000, 2_000, 5_000) == {:suspended, 60_000}
    end

    test "a clock set back is not a resume" do
      assert Resume.suspended(10_000, 0, 2_000, 5_000) == :awake
    end
  end

  describe "after a resume" do
    # ex_tauri's own ticks every 2 s; this one, alone in the test, ticks fast so
    # the resume is seen soon. ex_tauri's is put back after.
    setup do
      :ok = Supervisor.terminate_child(ExTauri.Supervisor, Resume)
      start_supervised!({Resume, tick: 50})
      on_exit(fn -> Supervisor.restart_child(ExTauri.Supervisor, Resume) end)
    end

    # As iOS leaves it: the BEAM frozen for a minute, its next tick far too late.
    defp suspend do
      :sys.replace_state(Resume, fn s -> %{s | last: s.last - 60_000} end)
    end

    defp listen do
      {:ok, listen} =
        :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

      {:ok, port} = :inet.port(listen)
      {listen, port}
    end

    defp next_message do
      receive do
        message -> message
      after
        5_000 -> flunk("nothing ran after the resume")
      end
    end

    test "gone listeners are restarted first, then every callback" do
      {gone, gone_port} = listen()
      {_kept, kept_port} = listen()
      me = self()

      # Registered before the listeners, run after them all the same.
      Resume.on_resume(:links, fn away -> send(me, {:callback, away}) end)
      Resume.watch(:gone, gone_port, fn -> send(me, :restarted_gone) end)
      Resume.watch(:kept, kept_port, fn -> send(me, :restarted_kept) end)
      Resume.on_resume(:bad, fn _ -> raise "boom" end)
      Resume.on_resume(:after_bad, fn _ -> send(me, :after_bad) end)
      :gen_tcp.close(gone)

      suspend()
      # All sent by one process, so they arrive in the order they ran.
      assert next_message() == :restarted_gone
      assert {:callback, away} = next_message()
      assert away >= 55_000
      assert next_message() == :after_bad
    end

    test "registering the same name again replaces it" do
      me = self()
      Resume.on_resume(:links, fn _ -> send(me, :old) end)
      Resume.on_resume(:links, fn _ -> send(me, :new) end)
      suspend()

      assert next_message() == :new
    end
  end

  test "ex_tauri starts it; an app listing it again gets :ignore, not a crash" do
    assert Process.whereis(Resume)
    assert Resume.start_link() == :ignore
  end
end
