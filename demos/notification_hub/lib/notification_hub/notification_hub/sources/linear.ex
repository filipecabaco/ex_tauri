defmodule NotificationHub.Notifications.Sources.Linear do
  @moduledoc "Fake Linear notification source."

  use NotificationHub.Notifications.Source,
    min_interval: 9_000,
    max_interval: 25_000,
    seed_count: 2

  alias NotificationHub.Notifications.{Notification, Source}

  @templates [
    {"issue_assigned", "Issue assigned: %{title}",
     "%{actor} assigned you to %{key}", :normal, []},
    {"issue_commented", "New comment on %{key}", "%{actor}: %{snippet}", :low, []},
    {"status_changed", "%{key} moved to In Review",
     "%{actor} moved \"%{title}\" to In Review", :normal,
     [%{id: "review", label: "Start review", style: :primary}]},
    {"priority_bumped", "%{key} bumped to Urgent",
     "%{actor} flagged \"%{title}\" as urgent", :urgent, []},
    {"mentioned", "Mentioned in %{key}",
     "%{actor} mentioned you: %{snippet}", :high, []}
  ]

  @actors ~w(fel amy tom ivan clara)
  @titles [
    "Unify notification events",
    "Fix flaky integration suite",
    "Onboarding polish",
    "Migrate storage layer",
    "Improve search ranking"
  ]
  @snippets [
    "can you take a look when you have a moment?",
    "this is blocking the release, mind jumping on it?",
    "I've added a repro in the ticket",
    "let's pair on this tomorrow",
    "small nit but worth fixing before merge"
  ]

  @impl true
  def info, do: %{key: :linear, name: "Linear", color: "indigo", icon: "hero-queue-list"}

  @impl true
  def generate do
    {kind, title_t, body_t, priority, extra_actions} = Enum.random(@templates)
    team = Enum.random(~w(ENG DES OPS GROW))
    num = :rand.uniform(999)
    key = "#{team}-#{num}"

    bindings = %{
      key: key,
      actor: Enum.random(@actors),
      title: Enum.random(@titles),
      snippet: Enum.random(@snippets)
    }

    %Notification{
      id: Notification.new_id(),
      source: :linear,
      kind: kind,
      title: render(title_t, bindings),
      body: render(body_t, bindings),
      actor: bindings.actor,
      url: "https://linear.app/example/issue/#{key}",
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
