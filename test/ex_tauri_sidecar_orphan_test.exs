defmodule ExTauri.Sidecar.OrphanTest do
  # Signals real OS processes and probes real ports, so it must not race
  # another test's listener.
  use ExUnit.Case, async: false

  alias ExTauri.Sidecar.Orphan

  # The exact shape `ps -o command=` prints for a shipped sidecar on each
  # platform. Burrito unpacks under Application Support on macOS and
  # ~/.local/share on Linux; both go through the same `.burrito/desktop_` dir.
  @macos "/Users/x/Library/Application Support/.burrito/desktop_erts-15.2.7.10_0.2.8/erts-15.2.7.10/bin/beam.smp -- -root ..."
  @linux "/home/x/.local/share/.burrito/desktop_erts-15.2.7.10_0.2.10/erts-15.2.7.10/bin/beam.smp -- -root ..."

  describe "packaged_sidecar?/2" do
    test "recognises a shipped sidecar on both platforms" do
      assert Orphan.packaged_sidecar?(@macos)
      assert Orphan.packaged_sidecar?(@linux)
    end

    test "ignores the release's own helper processes" do
      # Same unpack directory, not the thing holding the port. Killing these
      # would tear the ports out from under a perfectly healthy sidecar.
      refute Orphan.packaged_sidecar?(
               "/Users/x/Library/Application Support/.burrito/desktop_erts-15.2.7.10_0.2.8/erts-15.2.7.10/bin/erl_child_setup 1024"
             )
    end

    test "ignores a development server" do
      # `mix ex_tauri.dev` runs a plain release that is regularly a child of
      # init and perfectly healthy, so only the packaged path is ever eligible.
      refute Orphan.packaged_sidecar?("/opt/erlang/erts-15.2/bin/beam.smp -- -root /opt/erlang")
      refute Orphan.packaged_sidecar?(nil)
    end

    test "ignores a CLI invocation of the same release" do
      # Burrito puts a subcommand's arguments after `-extra`. `myapp status` run
      # from a terminal shares the unpack directory and the payload with the
      # sidecar, but it never had a window, and it is regularly a child of init.
      refute Orphan.packaged_sidecar?(@linux <> " -- -- -extra mcp bridge")
      assert Orphan.packaged_sidecar?(@linux <> " -- -- -extra")
    end

    test "follows a release name other than the scaffolded :desktop" do
      command = String.replace(@linux, "desktop_erts", "console_erts")

      refute Orphan.packaged_sidecar?(command)
      assert Orphan.packaged_sidecar?(command, release_name: "console")
    end
  end

  describe "identify/2" do
    setup do
      # A real unpack directory, because the payload is the only thing that
      # separates two ex_tauri apps: `mix ex_tauri.install` scaffolds the
      # release as `:desktop` for everyone, so they share this directory.
      root =
        Path.join([
          System.tmp_dir!(),
          "ex_tauri orphan test #{System.unique_integer([:positive])}",
          ".burrito",
          "desktop_erts-15.2.7.10_0.6.0"
        ])

      on_exit(fn -> File.rm_rf(Path.dirname(Path.dirname(root))) end)

      %{root: root}
    end

    test "recognises our own release", %{root: root} do
      unpack(root, "my_app-0.2.10")

      assert :ours = Orphan.identify(command_in(root), otp_app: :my_app)
    end

    test "refuses to claim another ex_tauri app's sidecar", %{root: root} do
      # The one that actually happened: four sidecars of a second app, versions
      # 0.3.0 through 0.6.0, in the shared `.burrito/desktop_*`. Reaping them
      # would have SIGTERMed a running app that was not ours.
      unpack(root, "someone_else-0.6.0")

      assert :foreign = Orphan.identify(command_in(root), otp_app: :my_app)
    end

    test "says it cannot tell when the unpack directory is gone", %{root: root} do
      # An upgrade that cleans up after itself leaves the old sidecar running
      # from a path that no longer exists. That process is the whole reason this
      # module exists, so it must not read as another app's.
      assert :unknown = Orphan.identify(command_in(root), otp_app: :my_app)
    end

    test "reads the root from argv[0], not from the -root that repeats later" do
      # Both paths are on every sidecar's command line. A greedy match takes the
      # last one, which on a machine running two ex_tauri apps is how ours gets
      # identified as theirs.
      ours = unpack_dir("ex_tauri argv0 ours")
      theirs = unpack_dir("ex_tauri argv0 theirs")

      on_exit(fn ->
        File.rm_rf(Path.dirname(Path.dirname(ours)))
        File.rm_rf(Path.dirname(Path.dirname(theirs)))
      end)

      unpack(ours, "my_app-0.2.10")
      unpack(theirs, "someone_else-0.6.0")

      command = "#{ours}/erts-15.2.7.10/bin/beam.smp -- -root #{theirs} -progname erl"

      assert :ours = Orphan.identify(command, otp_app: :my_app)
    end

    test "falls back to the sanitised :app_name when no :otp_app is given", %{root: root} do
      Application.put_env(:ex_tauri, :app_name, "My App")
      on_exit(fn -> Application.delete_env(:ex_tauri, :app_name) end)

      unpack(root, "my_app-0.2.10")

      assert :ours = Orphan.identify(command_in(root))
    end

    test "cannot tell for anything that is not a packaged sidecar" do
      assert :unknown = Orphan.identify(nil)
      assert :unknown = Orphan.identify("/opt/erlang/erts-15.2/bin/beam.smp -- -root /opt/erlang")
    end
  end

  describe "reclaim_port/2" do
    test "reports a port nobody holds as free" do
      assert :free = Orphan.reclaim_port(free_port())
    end

    test "refuses to evict a listener that is not an abandoned sidecar" do
      port = free_port()

      {:ok, socket} =
        :gen_tcp.listen(port, [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true])

      on_exit(fn -> :gen_tcp.close(socket) end)

      assert {:blocked, reason} = Orphan.reclaim_port(port)
      assert reason =~ "#{port}"
    end
  end

  describe "orphan_sidecar?/2" do
    test "never nominates the current process" do
      # It has a live parent and is not packaged, but the identity check has to
      # hold on its own: a sidecar must never signal itself.
      assert {pid, _rest} = Integer.parse(System.pid())
      refute Orphan.orphan_sidecar?(pid)
    end

    test "is false for a pid that does not exist" do
      refute Orphan.orphan_sidecar?(999_999)
    end
  end

  describe "orphan?/0 and packaged?/0" do
    test "the test VM has its parent and is not a packaged sidecar" do
      refute Orphan.orphan?()
      refute Orphan.packaged?()
    end
  end

  # `lib/<app>-<vsn>` is what Burrito unpacks and what identify/2 reads.
  defp unpack(root, app), do: File.mkdir_p!(Path.join([root, "lib", app]))

  defp unpack_dir(label) do
    Path.join([
      System.tmp_dir!(),
      "#{label} #{System.unique_integer([:positive])}",
      ".burrito",
      "desktop_erts-15.2.7.10_0.6.0"
    ])
  end

  # The shape `ps -o command=` prints: the emulator inside the unpack root, then
  # the same root again behind `-root`.
  defp command_in(root),
    do: "#{root}/erts-15.2.7.10/bin/beam.smp -- -root #{root} -progname erl"

  # Bind on 0 to have the OS name a port, then release it. Racy in principle,
  # but nothing else in this suite binds a fixed port.
  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
end
