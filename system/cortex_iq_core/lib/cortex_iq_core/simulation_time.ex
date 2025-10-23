defmodule CortexIqCore.SimulationTime do
  @moduledoc """
  Utilities for working with simulation time.

  The simulation runs at a configurable speed multiplier (default: 105,120x).
  This means 1 year of simulation time = 5 minutes of real time.

  ## Time Periods
  - Day: 6:00 AM - 6:00 PM (simulation time)
  - Night: 6:00 PM - 6:00 AM (simulation time)
  """

  @type t :: DateTime.t()

  @day_start_hour 6
  @day_end_hour 18

  @doc """
  Check if a given simulation time is during the day (6am-6pm).
  """
  @spec is_day?(DateTime.t()) :: boolean()
  def is_day?(%DateTime{} = dt) do
    hour = dt.hour
    hour >= @day_start_hour and hour < @day_end_hour
  end

  @doc """
  Check if a given simulation time is during the night (6pm-6am).
  """
  @spec is_night?(DateTime.t()) :: boolean()
  def is_night?(dt), do: not is_day?(dt)

  @doc """
  Calculate simulation time based on real elapsed time and speed multiplier.

  ## Examples

      iex> start_sim = ~U[2025-01-01 00:00:00Z]
      iex> start_real_ms = 1000
      iex> current_real_ms = 2000
      iex> speed = 105_120
      iex> CortexIqCore.SimulationTime.calculate(start_sim, start_real_ms, current_real_ms, speed)
      # Returns simulation time 1 second * 105,120 = 29.2 hours later

  """
  @spec calculate(DateTime.t(), integer(), integer(), integer()) :: DateTime.t()
  def calculate(start_simulation_time, start_real_ms, current_real_ms, speed) do
    real_elapsed_ms = current_real_ms - start_real_ms
    simulation_elapsed_ms = real_elapsed_ms * speed
    DateTime.add(start_simulation_time, simulation_elapsed_ms, :millisecond)
  end

  @doc """
  Calculate real-time duration in milliseconds for a given simulation duration.

  ## Examples

      iex> CortexIqCore.SimulationTime.real_duration_ms(3600, 105_120)  # 1 simulation hour
      34  # ~34 real milliseconds

  """
  @spec real_duration_ms(integer(), integer()) :: integer()
  def real_duration_ms(simulation_seconds, speed) do
    div(simulation_seconds * 1000, speed)
  end

  @doc """
  Add months to a datetime (handles month boundaries correctly).
  """
  @spec add_months(DateTime.t(), integer()) :: DateTime.t()
  def add_months(%DateTime{} = dt, months) do
    # Convert to naive datetime, add months, convert back
    naive = DateTime.to_naive(dt)
    new_naive = NaiveDateTime.add(naive, months * 30 * 24 * 3600, :second)
    DateTime.from_naive!(new_naive, "Etc/UTC")
  end

  @doc """
  Calculate days between two datetimes.
  """
  @spec days_between(DateTime.t(), DateTime.t()) :: integer()
  def days_between(%DateTime{} = dt1, %DateTime{} = dt2) do
    diff_seconds = DateTime.diff(dt2, dt1, :second)
    div(diff_seconds, 86400)
  end

  @doc """
  Check if datetime is within 1 day of expiry (for discount eligibility).
  """
  @spec within_discount_window?(DateTime.t(), DateTime.t()) :: boolean()
  def within_discount_window?(%DateTime{} = current_time, %DateTime{} = expiry_time) do
    days_until_expiry = days_between(current_time, expiry_time)
    days_until_expiry == 1
  end
end
