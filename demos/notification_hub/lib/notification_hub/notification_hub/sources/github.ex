defmodule NotificationHub.Notifications.Sources.GitHub do
  @moduledoc "Fake GitHub notification source."

  use NotificationHub.Notifications.Source,
    min_interval: 6_000,
    max_interval: 20_000,
    seed_count: 3

  alias NotificationHub.Notifications.{Notification, Source}

  @templates [
    {"pr_review_requested", "Review requested on PR #%{num}",
     "%{actor} wants you to review \"%{title}\"", :high,
     [%{id: "approve", label: "Approve", style: :success}]},
    {"pr_approved", "PR #%{num} approved", "%{actor} approved your pull request", :normal, []},
    {"issue_assigned", "Issue #%{num} assigned",
     "%{actor} assigned you to \"%{title}\"", :normal, []},
    {"mention", "Mentioned in #%{num}",
     "%{actor} mentioned you in a comment thread", :normal, []},
    {"ci_failed", "CI failed on PR #%{num}",
     "Build for \"%{title}\" failed — check the logs", :urgent,
     [%{id: "retry", label: "Retry build", style: :warning}]},
    {"new_release", "New release published",
     "%{actor} published v%{num} of the repository", :low, []}
  ]

  @actors ~w(octocat mona wes rita luis sara miguel ana)
  @titles [
    "Fix token refresh regression",
    "Bump deps to the latest minor",
    "Feature: realtime sync",
    "Docs: add demo apps",
    "Refactor notification hub",
    "Ship new settings screen"
  ]

  @impl true
  def info, do: %{key: :github, name: "GitHub", color: "slate", icon: "hero-code-bracket"}

  @impl true
  def generate do
    {kind, title_t, body_t, priority, extra_actions} = Enum.random(@templates)
    actor = Enum.random(@actors)
    num = :rand.uniform(9_999)
    title = Enum.random(@titles)
    bindings = %{num: num, actor: actor, title: title}

    %Notification{
      id: Notification.new_id(),
      source: :github,
      kind: kind,
      title: render(title_t, bindings),
      body: render(body_t, bindings),
      actor: actor,
      url: "https://github.com/example/repo/pull/#{num}",
      priority: priority,
      received_at: DateTime.utc_now(),
      actions: Source.default_actions() ++ extra_actions
    }
  end

  defp render(template, bindings) do
    Enum.reduce(bindings, template, fn {k, v}, acc ->
      String.replace(acc, "%{#{k}}", to_string(v))
    end)
  end
end
