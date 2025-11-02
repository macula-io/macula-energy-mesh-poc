defmodule CortexIqDashboardSchemas.HomeStatus do
  @moduledoc """
  BitFlag-based home status management using BCUtils.BitFlags pattern.

  Home lifecycle states are represented as bit flags that can be combined:
  - Multiple states can be active simultaneously
  - Status transitions are explicit (reserved → initialized → connected/disconnected)
  - Easy to query specific states or combinations

  ## Status Flags

  - `0` - None (no status set)
  - `1` - Reserved (home_id reserved in database, awaiting initialization)
  - `2` - Initialized (home.initialized event processed, full data available)
  - `4` - Connected (home.connected event processed, actively participating)
  - `8` - Disconnected (home.disconnected event processed, offline)
  - `16` - Active (currently processing events and participating in market)
  - `32` - Error (in error state, needs attention)

  ## Example Status Combinations

  - `0` = No status (should never happen for valid homes)
  - `1` = Reserved only (waiting for home.initialized)
  - `3` = Reserved + Initialized (1 + 2)
  - `7` = Reserved + Initialized + Connected (1 + 2 + 4)
  - `23` = Reserved + Initialized + Connected + Active (1 + 2 + 4 + 16)
  - `11` = Reserved + Initialized + Disconnected (1 + 2 + 8)

  ## Usage

      iex> status = 0
      iex> status = HomeStatus.set_reserved(status)
      1
      iex> status = HomeStatus.set_initialized(status)
      3
      iex> status = HomeStatus.set_connected(status)
      7
      iex> HomeStatus.is_connected?(status)
      true
      iex> HomeStatus.to_string(status)
      "Reserved, Initialized, Connected"
  """

  import Bitwise

  # Status flag bit values
  @none          0
  @reserved      1  # 0b00000001
  @initialized   2  # 0b00000010
  @connected     4  # 0b00000100
  @disconnected  8  # 0b00001000
  @active       16  # 0b00010000
  @error        32  # 0b00100000

  # Flag descriptions for display
  @flag_map %{
    @none          => "None",
    @reserved      => "Reserved",
    @initialized   => "Initialized",
    @connected     => "Connected",
    @disconnected  => "Disconnected",
    @active        => "Active",
    @error         => "Error"
  }

  # Public accessors
  def none, do: @none
  def reserved, do: @reserved
  def initialized, do: @initialized
  def connected, do: @connected
  def disconnected, do: @disconnected
  def active, do: @active
  def error, do: @error

  def flag_map, do: @flag_map

  # Set status flags
  def set_reserved(status), do: status ||| @reserved
  def set_initialized(status), do: status ||| @initialized
  def set_connected(status), do: status ||| @connected
  def set_disconnected(status), do: status ||| @disconnected
  def set_active(status), do: status ||| @active
  def set_error(status), do: status ||| @error

  # Unset status flags
  def unset_reserved(status), do: status &&& bnot(@reserved)
  def unset_initialized(status), do: status &&& bnot(@initialized)
  def unset_connected(status), do: status &&& bnot(@connected)
  def unset_disconnected(status), do: status &&& bnot(@disconnected)
  def unset_active(status), do: status &&& bnot(@active)
  def unset_error(status), do: status &&& bnot(@error)

  # Check status flags
  def is_reserved?(status), do: (status &&& @reserved) == @reserved
  def is_initialized?(status), do: (status &&& @initialized) == @initialized
  def is_connected?(status), do: (status &&& @connected) == @connected
  def is_disconnected?(status), do: (status &&& @disconnected) == @disconnected
  def is_active?(status), do: (status &&& @active) == @active
  def is_error?(status), do: (status &&& @error) == @error

  @doc """
  Returns a list of status flag descriptions that are currently set.

  ## Examples

      iex> HomeStatus.to_list(7)
      ["Reserved", "Initialized", "Connected"]

      iex> HomeStatus.to_list(0)
      ["None"]
  """
  def to_list(0), do: [@flag_map[@none]]

  def to_list(status) when status > 0 do
    [@reserved, @initialized, @connected, @disconnected, @active, @error]
    |> Enum.filter(fn flag -> (status &&& flag) == flag end)
    |> Enum.map(fn flag -> @flag_map[flag] end)
  end

  @doc """
  Returns a comma-separated string of active status flags.

  ## Examples

      iex> HomeStatus.to_string(7)
      "Reserved, Initialized, Connected"
  """
  def to_string(status) do
    to_list(status) |> Enum.join(", ")
  end

  @doc """
  Returns the highest (most recent) status flag set.

  ## Examples

      iex> HomeStatus.highest(7)
      "Connected"
  """
  def highest(status) do
    to_list(status) |> List.last() || @flag_map[@none]
  end

  @doc """
  Returns the lowest (earliest) status flag set.

  ## Examples

      iex> HomeStatus.lowest(7)
      "Reserved"
  """
  def lowest(status) do
    to_list(status) |> List.first() || @flag_map[@none]
  end

  @doc """
  Transition from disconnected to connected state.
  Unsets disconnected flag and sets connected flag.
  """
  def connect(status) do
    status
    |> unset_disconnected()
    |> set_connected()
  end

  @doc """
  Transition from connected to disconnected state.
  Unsets connected and active flags, sets disconnected flag.
  """
  def disconnect(status) do
    status
    |> unset_connected()
    |> unset_active()
    |> set_disconnected()
  end
end
