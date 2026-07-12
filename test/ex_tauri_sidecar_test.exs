defmodule ExTauri.SidecarTest do
  # async: false — these exercise config-driven resolution via Application env.
  use ExUnit.Case, async: false

  alias ExTauri.Sidecar

  defmodule CustomShim do
    @behaviour ExTauri.Sidecar
    @impl true
    def script(%{project_root: root}), do: "#!/bin/sh\ncd #{root} && exec mix run --no-halt\n"
  end

  describe "resolve/1" do
    test "maps built-in names to their modules" do
      assert Sidecar.resolve(:phx_server) == ExTauri.Sidecar.DevServer
      assert Sidecar.resolve(:dev_server) == ExTauri.Sidecar.DevServer
      assert Sidecar.resolve(:release) == ExTauri.Sidecar.Release
    end

    test "resolves a module that implements the behaviour directly" do
      assert Sidecar.resolve(CustomShim) == CustomShim
    end

    test "resolves names registered via config" do
      Application.put_env(:ex_tauri, :sidecars, %{custom: CustomShim})
      on_exit(fn -> Application.delete_env(:ex_tauri, :sidecars) end)

      assert Sidecar.resolve(:custom) == CustomShim
    end

    test "raises an actionable error for an unknown name" do
      assert_raise ArgumentError, ~r/Unknown sidecar :nope/, fn ->
        Sidecar.resolve(:nope)
      end
    end
  end

  describe "generate/2" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      # Override triplet/path/root so generation never shells out to rustc.
      %{
        ctx: [
          triplet: "test-triple",
          project_root: tmp_dir,
          path: Path.join(tmp_dir, "burrito_out/desktop-test-triple")
        ]
      }
    end

    test "writes an executable dev-server shim (default: mix phx.server)", %{ctx: ctx} do
      assert :ok = Sidecar.generate(:phx_server, ctx)
      path = ctx[:path]

      assert File.read!(path) =~ "exec mix phx.server"
      assert %File.Stat{mode: mode} = File.stat!(path)
      assert Bitwise.band(mode, 0o111) != 0
    end

    test "dev-server command is configurable (not tied to Phoenix)", %{ctx: ctx} do
      Application.put_env(:ex_tauri, :dev_command, ~w(mix francis.server))
      on_exit(fn -> Application.delete_env(:ex_tauri, :dev_command) end)

      assert :ok = Sidecar.generate(:phx_server, ctx)
      assert File.read!(ctx[:path]) =~ "exec mix francis.server"
    end

    test "generates a custom shim from a registered module", %{ctx: ctx} do
      Application.put_env(:ex_tauri, :sidecars, %{custom: CustomShim})
      on_exit(fn -> Application.delete_env(:ex_tauri, :sidecars) end)

      assert :ok = Sidecar.generate(:custom, ctx)
      assert File.read!(ctx[:path]) =~ "exec mix run --no-halt"
    end
  end
end
