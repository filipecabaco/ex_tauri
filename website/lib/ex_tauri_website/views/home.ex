defmodule ExTauriWebsite.Views.Home do
  require EEx

  EEx.function_from_file(:def, :index, "lib/ex_tauri_website/views/home/index.html.eex", [
    :assigns
  ])

  def static_path(logical_path) do
    Francis.Static.static_path(logical_path, "/assets")
  end
end
