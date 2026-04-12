defmodule ExampleDesktop.NotificationHub.Sources.Gmail do
  @moduledoc """
  Fake Gmail notification source.

  A real adapter would use Gmail's push notifications (Cloud Pub/Sub) or
  poll the REST API to surface unread conversations. Here we just pick
  senders and subjects from a small pool to demo the pipeline.
  """

  use ExampleDesktop.NotificationHub.Source,
    min_interval: 12_000,
    max_interval: 30_000,
    seed_count: 2

  alias ExampleDesktop.NotificationHub.{Notification, Source}

  @templates [
    {"inbox", "%{subject}", "From %{actor} — %{snippet}", :normal,
     [%{id: "reply", label: "Reply", style: :primary}]},
    {"important", "Important: %{subject}", "From %{actor} — %{snippet}", :high,
     [%{id: "reply", label: "Reply", style: :primary}]},
    {"calendar", "Meeting: %{subject}",
     "Invite from %{actor} for tomorrow", :normal,
     [%{id: "accept", label: "Accept", style: :success}]}
  ]

  @actors [
    "jane@acme.co",
    "hiring@example.com",
    "billing@stripe.com",
    "newsletter@elixirweekly.net",
    "alice@partner.io",
    "notifications@github.com"
  ]

  @subjects [
    "Quick question about the demo",
    "Q2 roadmap draft",
    "Invoice for April",
    "Elixir Weekly #400",
    "Re: integration follow-up",
    "Welcome to the team"
  ]

  @snippets [
    "Just wanted to loop you in on the latest...",
    "Please review when you have a minute.",
    "Attaching the updated spec for your feedback.",
    "We'd love to hear your thoughts on the proposal.",
    "Let's confirm the agenda for tomorrow's sync."
  ]

  @impl true
  def info, do: %{key: :gmail, name: "Gmail", color: "rose", icon: "hero-envelope"}

  @impl true
  def generate do
    {kind, title_t, body_t, priority, extra_actions} = Enum.random(@templates)

    bindings = %{
      actor: Enum.random(@actors),
      subject: Enum.random(@subjects),
      snippet: Enum.random(@snippets)
    }

    %Notification{
      id: Notification.new_id(),
      source: :gmail,
      kind: kind,
      title: render(title_t, bindings),
      body: render(body_t, bindings),
      actor: bindings.actor,
      url: "https://mail.google.com/mail/u/0/#inbox",
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
