defmodule NotificationHub.Notifications.Notification do
  @moduledoc """
  A normalised notification record.

  The hub aggregates events from different providers (GitHub, Linear,
  Gmail, Slack) into this common shape so the UI can treat them
  uniformly. In a production integration the concrete sources would
  populate this struct from their respective API payloads.
  """

  @type source :: :github | :linear | :gmail | :slack
  @type priority :: :low | :normal | :high | :urgent

  @type action :: %{id: String.t(), label: String.t(), style: atom()}

  @type t :: %__MODULE__{
          id: String.t(),
          source: source(),
          kind: String.t(),
          title: String.t(),
          body: String.t() | nil,
          actor: String.t() | nil,
          url: String.t() | nil,
          priority: priority(),
          received_at: DateTime.t(),
          read: boolean(),
          dismissed: boolean(),
          snoozed_until: DateTime.t() | nil,
          actions: [action()]
        }

  @enforce_keys [:id, :source, :kind, :title, :received_at]
  defstruct id: nil,
            source: nil,
            kind: nil,
            title: nil,
            body: nil,
            actor: nil,
            url: nil,
            priority: :normal,
            received_at: nil,
            read: false,
            dismissed: false,
            snoozed_until: nil,
            actions: []

  def new_id do
    :crypto.strong_rand_bytes(8) |> Base.hex_encode32(padding: false, case: :lower)
  end

  def snoozed?(%__MODULE__{snoozed_until: nil}), do: false

  def snoozed?(%__MODULE__{snoozed_until: %DateTime{} = until}) do
    DateTime.compare(until, DateTime.utc_now()) == :gt
  end
end
