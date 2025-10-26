defmodule CortexIqDashboard.Schemas.ContractEvent do
  @moduledoc """
  Ecto schema for contract lifecycle events (signed, switched, expired).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "contract_events" do
    field :contract_id, :string
    field :home_id, :string
    field :provider_id, :string
    field :event_type, :string
    field :simulation_time, :utc_datetime_usec
    field :start_date, :utc_datetime_usec
    field :end_date, :utc_datetime_usec
    field :day_buy_price, :float
    field :night_buy_price, :float
    field :day_sell_price, :float
    field :night_sell_price, :float
    field :switching_discount, :float
    field :previous_contract_id, :string
    field :previous_provider_id, :string
    field :switch_reason, :string
    field :projected_savings, :float
    field :days_before_expiry, :integer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :contract_id,
      :home_id,
      :provider_id,
      :event_type,
      :simulation_time,
      :start_date,
      :end_date,
      :day_buy_price,
      :night_buy_price,
      :day_sell_price,
      :night_sell_price,
      :switching_discount,
      :previous_contract_id,
      :previous_provider_id,
      :switch_reason,
      :projected_savings,
      :days_before_expiry
    ])
    |> validate_required([
      :contract_id,
      :home_id,
      :provider_id,
      :event_type,
      :simulation_time
    ])
    |> validate_inclusion(:event_type, ["signed", "switched", "expired"])
  end

  def from_wamp_event(event_type, event_data) do
    %{
      contract_id: event_data["contract_id"],
      home_id: event_data["home_id"],
      provider_id: event_data["provider_id"],
      event_type: event_type,
      simulation_time: parse_datetime(event_data["simulation_time"]),
      start_date: parse_datetime(event_data["start_date"]),
      end_date: parse_datetime(event_data["end_date"]),
      day_buy_price: event_data["day_buy_price"],
      night_buy_price: event_data["night_buy_price"],
      day_sell_price: event_data["day_sell_price"],
      night_sell_price: event_data["night_sell_price"],
      switching_discount: event_data["switching_discount"],
      previous_contract_id: event_data["previous_contract_id"],
      previous_provider_id: event_data["previous_provider_id"],
      switch_reason: event_data["switch_reason"],
      projected_savings: event_data["projected_savings"],
      days_before_expiry: event_data["days_before_expiry"]
    }
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(iso8601_string) when is_binary(iso8601_string) do
    case DateTime.from_iso8601(iso8601_string) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(datetime), do: datetime
end
