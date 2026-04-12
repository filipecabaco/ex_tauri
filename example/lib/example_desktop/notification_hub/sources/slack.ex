defmodule ExampleDesktop.NotificationHub.Sources.Slack do
  @moduledoc """
  Fake Slack notification source.

  A real adapter would use Slack's Events API (via a websocket or the
  HTTP callback) to produce notifications for mentions, DMs and channel
  threads the user is subscribed to.
  """

  use ExampleDesktop.NotificationHub.Source,
    min_interval: 5_000,
    max_interval: 15_000,
    seed_count: 3

  alias ExampleDesktop.NotificationHub.{Notification, Source}

  @templates [
    {"mention", "Mention in #%{channel}", "@%{actor}: %{snippet}", :high,
     [%{id: "reply", label: "Reply in thread", style: :primary}]},
    {"dm", "DM from %{actor}", "%{snippet}", :normal,
     [%{id: "reply", label: "Reply", style: :primary}]},
    {"thread_reply", "New reply in #%{channel}",
     "%{actor} replied: %{snippet}", :low, []},
    {"huddle", "Huddle starting in #%{channel}",
     "%{actor} started a huddle", :normal,
     [%{id: "join", label: "Join huddle", style: :success}]}
  ]

  @channels ~w(general engineering random product design releases support)
  @actors ~w(filipe jess marie karl pat sam)

  @snippets [
    "can you take a look at this when you have a sec?",
    "anyone have cycles to jump on a bug?",
    "shipping in 10 minutes — last call for review",
    "reminder: standup moved to 10:30",
    "I updated the runbook, please skim",
    "heads up: CI is flaky on main right now"
  ]

  @impl true
  def info, do: %{key: :slack, name: "Slack", color: "emerald", icon: "hero-chat-bubble-left-right"}

  @impl true
  def generate do
    {kind, title_t, body_t, priority, extra_actions} = Enum.random(@templates)

    bindings = %{
      channel: Enum.random(@channels),
      actor: Enum.random(@actors),
      snippet: Enum.random(@snippets)
    }

    %Notification{
      id: Notification.new_id(),
      source: :slack,
      kind: kind,
      title: render(title_t, bindings),
      body: render(body_t, bindings),
      actor: bindings.actor,
      url: "https://app.slack.com/client/T000/C000",
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
