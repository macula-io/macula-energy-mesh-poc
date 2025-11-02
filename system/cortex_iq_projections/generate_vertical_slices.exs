#!/usr/bin/env elixir

defmodule VerticalSliceGenerator do
  @moduledoc """
  Generates vertical slice files for projection systems.

  Usage:
    ./generate_vertical_slices.exs
  """

  @base_path "lib/cortex_iq_projections"

  defmodule SliceConfig do
    defstruct [
      :name,              # e.g., "project_home_initialized"
      :module_name,       # e.g., "ProjectHomeInitialized"
      :topic,             # e.g., "be.cortexiq.home.initialized"
      :volume,            # :high or :low
      :description,       # Brief description
      :projection_logic   # Function to generate projection code
    ]
  end

  def run do
    IO.puts("\n🔧 Generating vertical slices for CortexIQ Projections...\n")

    slices = [
      # Home events (low volume - lifecycle events)
      %SliceConfig{
        name: "project_home_initialized",
        module_name: "ProjectHomeInitialized",
        topic: "be.cortexiq.home.initialized",
        volume: :low,
        description: "Projects home.initialized events (home creation)",
        projection_logic: &home_initialized_projection/0
      },
      %SliceConfig{
        name: "project_home_connected",
        module_name: "ProjectHomeConnected",
        topic: "be.cortexiq.home.connected",
        volume: :low,
        description: "Projects home.connected events (WAMP connection)",
        projection_logic: &home_connected_projection/0
      },
      %SliceConfig{
        name: "project_home_disconnected",
        module_name: "ProjectHomeDisconnected",
        topic: "be.cortexiq.home.disconnected",
        volume: :low,
        description: "Projects home.disconnected events (WAMP disconnection)",
        projection_logic: &home_disconnected_projection/0
      },
      %SliceConfig{
        name: "project_home_traded",
        module_name: "ProjectHomeTraded",
        topic: "be.cortexiq.home.traded",
        volume: :low,
        description: "Projects home.traded events (energy buy/sell transactions)",
        projection_logic: &home_traded_projection/0
      },

      # Balance tracking
      %SliceConfig{
        name: "project_balance_updated",
        module_name: "ProjectBalanceUpdated",
        topic: "be.cortexiq.balance.updated",
        volume: :low,
        description: "Projects balance.updated events (cumulative energy balance)",
        projection_logic: &balance_updated_projection/0
      },

      # Market events
      %SliceConfig{
        name: "project_market_contract_proposed",
        module_name: "ProjectMarketContractProposed",
        topic: "be.cortexiq.market.contract_proposed",
        volume: :low,
        description: "Projects market.contract_proposed events",
        projection_logic: &contract_proposed_projection/0
      },
      %SliceConfig{
        name: "project_market_contract_confirmed",
        module_name: "ProjectMarketContractConfirmed",
        topic: "be.cortexiq.market.contract_confirmed",
        volume: :low,
        description: "Projects market.contract_confirmed events",
        projection_logic: &contract_confirmed_projection/0
      },
      %SliceConfig{
        name: "project_market_contract_rejected",
        module_name: "ProjectMarketContractRejected",
        topic: "be.cortexiq.market.contract_rejected",
        volume: :low,
        description: "Projects market.contract_rejected events",
        projection_logic: &contract_rejected_projection/0
      },
      %SliceConfig{
        name: "project_market_contract_expired",
        module_name: "ProjectMarketContractExpired",
        topic: "be.cortexiq.market.contract_expired",
        volume: :low,
        description: "Projects market.contract_expired events",
        projection_logic: &contract_expired_projection/0
      },
      %SliceConfig{
        name: "project_market_trade_executed",
        module_name: "ProjectMarketTradeExecuted",
        topic: "be.cortexiq.market.trade_executed",
        volume: :low,
        description: "Projects market.trade_executed events (grid transactions)",
        projection_logic: &trade_executed_projection/0
      },
      %SliceConfig{
        name: "project_market_savings_realized",
        module_name: "ProjectMarketSavingsRealized",
        topic: "be.cortexiq.market.savings_realized",
        volume: :low,
        description: "Projects market.savings_realized events (CortexIQ commission)",
        projection_logic: &savings_realized_projection/0
      },
      %SliceConfig{
        name: "project_market_spot_price_updated",
        module_name: "ProjectMarketSpotPriceUpdated",
        topic: "be.cortexiq.market.spot_price_updated",
        volume: :low,
        description: "Projects market.spot_price_updated events",
        projection_logic: &spot_price_updated_projection/0
      },

      # Arbitrage events
      %SliceConfig{
        name: "project_arbitrage_profit_realized",
        module_name: "ProjectArbitrageProfitRealized",
        topic: "be.cortexiq.arbitrage.profit_realized",
        volume: :low,
        description: "Projects arbitrage.profit_realized events (battery arbitrage)",
        projection_logic: &arbitrage_profit_projection/0
      },

      # Simulation events
      %SliceConfig{
        name: "project_simulation_reset",
        module_name: "ProjectSimulationReset",
        topic: "be.cortexiq.simulation.reset",
        volume: :low,
        description: "Projects simulation.reset events (clear all state)",
        projection_logic: &simulation_reset_projection/0
      }
    ]

    Enum.each(slices, &generate_slice/1)

    IO.puts("\n✅ Generated #{length(slices)} vertical slices!")
    IO.puts("\nNext steps:")
    IO.puts("  1. Review generated files")
    IO.puts("  2. Update application.ex to add new slices to supervision tree")
    IO.puts("  3. Compile: mix compile")
    IO.puts("  4. Test deployment\n")
  end

  defp generate_slice(config) do
    IO.puts("📝 Generating #{config.name}...")

    dir_path = Path.join(@base_path, config.name)
    File.mkdir_p!(dir_path)

    # Generate system.ex
    system_content = generate_system(config)
    File.write!(Path.join(dir_path, "system.ex"), system_content)

    # Generate subscriber.ex
    subscriber_content = generate_subscriber(config)
    File.write!(Path.join(dir_path, "subscriber.ex"), subscriber_content)

    # Generate projector.ex
    projector_content = generate_projector(config)
    File.write!(Path.join(dir_path, "projector.ex"), projector_content)

    IO.puts("   ✓ Created #{dir_path}/")
  end

  # Template generators

  defp generate_system(config) do
    """
    defmodule CortexIqProjections.#{config.module_name}.System do
      @moduledoc \"\"\"
      Supervises the complete vertical slice for projecting #{String.replace(config.topic, "be.cortexiq.", "")} events.

      #{config.description}

      ## Architecture

      WAMP Client → Subscriber → #{if config.volume == :high, do: "Broadway", else: "GenServer"} Projector → Database

      ## Strategy

      Uses `:rest_for_one` strategy for cascading restart behavior.
      \"\"\"
      use Supervisor
      require Logger

      def start_link(opts) do
        Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl true
      def init(opts) do
        bondy_url = Keyword.get(opts, :bondy_url, System.get_env("BONDY_URL", "ws://localhost:18080/ws"))
        realm_uri = Keyword.get(opts, :realm_uri, System.get_env("BONDY_REALM", "be.cortexiq.energy"))

        # Unique WAMP client name for this event type
        wamp_client_name = :wamp_#{config.name}

        Logger.info("#{config.module_name}.System starting")
        Logger.info("  WAMP client: \#{inspect(wamp_client_name)}")

        children = [
          # 1. WAMP Client
          %{
            id: wamp_client_name,
            start: {MaculaSdk.Wamp, :start_link, [[
              url: bondy_url,
              realm: realm_uri,
              name: wamp_client_name
            ]]},
            type: :worker,
            restart: :permanent,
            shutdown: 5000
          },

          # 2. Subscriber
          {CortexIqProjections.#{config.module_name}.Subscriber, [
            wamp_client: wamp_client_name
          ]},

          # 3. #{if config.volume == :high, do: "Broadway", else: "GenServer"} Projector
          {CortexIqProjections.#{config.module_name}.Projector, []}
        ]

        Supervisor.init(children, strategy: :rest_for_one)
      end
    end
    """
  end

  defp generate_subscriber(config) do
    """
    defmodule CortexIqProjections.#{config.module_name}.Subscriber do
      @moduledoc \"\"\"
      Subscribes to #{config.topic} WAMP events and forwards to projector.

      #{config.description}

      ## Event Flow

      WAMP → handle_event/2 → #{if config.volume == :high, do: "Broadway.push_messages/2", else: "GenServer.cast/2"} → Projector
      \"\"\"
      use GenServer
      require Logger
      alias MaculaSdk.Wamp.Client

      defmodule State do
        @moduledoc false
        defstruct [:wamp_client, :subscription_status]
      end

      # Client API

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      # GenServer Callbacks

      @impl true
      def init(opts) do
        wamp_client = Keyword.fetch!(opts, :wamp_client)

        state = %State{
          wamp_client: wamp_client,
          subscription_status: :not_subscribed
        }

        Process.send_after(self(), :subscribe, 2000)

        {:ok, state}
      end

      @impl true
      def handle_info(:subscribe, %{wamp_client: wamp_client} = state) do
        topic = "#{config.topic}"

        Logger.info("#{config.module_name}.Subscriber: Subscribing to \#{topic}")

        case Client.subscribe(wamp_client, topic, &handle_event/2, %{}) do
          :ok ->
            Logger.info("#{config.module_name}.Subscriber: ✓ Subscribed to \#{topic}")
            {:noreply, %{state | subscription_status: :subscribed}}

          {:error, reason} ->
            Logger.error("#{config.module_name}.Subscriber: ✗ Failed: \#{inspect(reason)}")
            Process.send_after(self(), :subscribe, 5000)
            {:noreply, state}
        end
      end

      def handle_info(msg, state) do
        Logger.debug("#{config.module_name}.Subscriber: Unexpected message: \#{inspect(msg)}")
        {:noreply, state}
      end

      # Event Handler

      defp handle_event(_topic, event_data) do
        CortexIqProjections.#{config.module_name}.Projector.project_event(event_data)
      end
    end
    """
  end

  defp generate_projector(config) do
    projection_code = config.projection_logic.()

    """
    defmodule CortexIqProjections.#{config.module_name}.Projector do
      @moduledoc \"\"\"
      #{if config.volume == :high, do: "Broadway", else: "GenServer"} projector for #{config.topic} events.

      #{config.description}
      \"\"\"
      use GenServer
      require Logger
      import Ecto.Query
      alias CortexIqProjections.Repo
      alias CortexIqDashboardSchemas.Projections.{HomeState, ProviderState, SystemStats}
      alias CortexIqDashboardSchemas.TimeSeries.{EnergyEvent, EnergyTrade, ContractEvent}

      # Client API

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      def project_event(event_data) do
        GenServer.cast(__MODULE__, {:project, event_data})
      end

      # GenServer Callbacks

      @impl true
      def init(_opts) do
        Logger.info("#{config.module_name}.Projector: Started")
        {:ok, %{}}
      end

      @impl true
      def handle_cast({:project, event_data}, state) do
        project_#{String.replace(config.name, "project_", "")}(event_data)
        {:noreply, state}
      end

      # Projection Logic

    #{projection_code}

      # Helper Functions

      defp parse_datetime(nil), do: nil

      defp parse_datetime(dt) when is_binary(dt) do
        case DateTime.from_iso8601(dt) do
          {:ok, datetime, _offset} -> datetime
          {:error, _} -> nil
        end
      end

      defp parse_datetime(%DateTime{} = dt), do: dt
    end
    """
  end

  # Projection logic generators

  defp home_initialized_projection do
    """
      defp project_home_initialized(event_data) do
        kwargs = Map.get(event_data, :kwargs, %{})

        home_id = kwargs["home_id"]
        name = kwargs["name"]
        iot_provider = kwargs["iot_provider"]
        location = kwargs["location"]
        postal_code = kwargs["postal_code"]
        region = kwargs["region"]
        solar_capacity_kw = kwargs["solar_capacity_kw"] || 5.0
        battery_capacity_kwh = kwargs["battery_capacity_kwh"] || 10.0
        simulation_time = parse_datetime(kwargs["simulation_time"])

        Repo.insert!(
          %HomeState{home_id: home_id},
          on_conflict: [
            set: [
              name: name,
              iot_provider: iot_provider,
              location: location,
              postal_code: postal_code,
              region: region,
              battery_capacity_kwh: battery_capacity_kwh,
              last_event_at: simulation_time,
              updated_at: DateTime.utc_now()
            ]
          ],
          conflict_target: :home_id
        )
      rescue
        error ->
          Logger.error("#{inspect(__MODULE__)}: Error: \#{inspect(error)}")
          Logger.error("Event data: \#{inspect(kwargs)}")
      end
    """
  end

  defp home_connected_projection do
    """
      defp project_home_connected(event_data) do
        kwargs = Map.get(event_data, :kwargs, %{})

        home_id = kwargs["home_id"]
        simulation_time = parse_datetime(kwargs["simulation_time"])

        Repo.insert!(
          %HomeState{home_id: home_id},
          on_conflict: [
            set: [
              connected_at: simulation_time,
              disconnected_at: nil,
              last_event_at: simulation_time,
              updated_at: DateTime.utc_now()
            ]
          ],
          conflict_target: :home_id
        )
      rescue
        error ->
          Logger.error("#{inspect(__MODULE__)}: Error: \#{inspect(error)}")
      end
    """
  end

  defp home_disconnected_projection do
    """
      defp project_home_disconnected(event_data) do
        kwargs = Map.get(event_data, :kwargs, %{})

        home_id = kwargs["home_id"]
        simulation_time = parse_datetime(kwargs["simulation_time"])

        Repo.insert!(
          %HomeState{home_id: home_id},
          on_conflict: [
            set: [
              disconnected_at: simulation_time,
              last_event_at: simulation_time,
              updated_at: DateTime.utc_now()
            ]
          ],
          conflict_target: :home_id
        )
      rescue
        error ->
          Logger.error("#{inspect(__MODULE__)}: Error: \#{inspect(error)}")
      end
    """
  end

  defp home_traded_projection do
    """
      defp project_home_traded(event_data) do
        kwargs = Map.get(event_data, :kwargs, %{})

        home_id = kwargs["home_id"]
        provider_id = kwargs["provider_id"]
        contract_id = kwargs["contract_id"]
        type = String.to_atom(kwargs["type"] || "buy")
        kwh = kwargs["kwh"] || 0.0
        price_per_kwh = kwargs["price_per_kwh"] || 0.0
        total = kwargs["total"] || 0.0
        is_day = kwargs["is_day"] || true
        simulation_time = parse_datetime(kwargs["simulation_time"])

        # Insert into energy_trades time-series table
        {import_kwh, export_kwh, import_cost, export_revenue} =
          case type do
            :buy -> {kwh, 0.0, total, 0.0}
            :sell -> {0.0, kwh, 0.0, total}
          end

        Repo.insert!(
          %EnergyTrade{
            home_id: home_id,
            provider_id: provider_id,
            contract_id: contract_id,
            simulation_time: simulation_time,
            simulation_hour: simulation_time.hour,
            grid_import_kwh: import_kwh,
            grid_export_kwh: export_kwh,
            import_price_per_kwh: if(type == :buy, do: price_per_kwh, else: nil),
            export_price_per_kwh: if(type == :sell, do: price_per_kwh, else: nil),
            is_day: is_day,
            import_cost: import_cost,
            export_revenue: export_revenue,
            net_cost: import_cost - export_revenue,
            recorded_at: DateTime.utc_now()
          },
          on_conflict: :nothing,
          conflict_target: [:home_id, :simulation_time]
        )
      rescue
        error ->
          Logger.error("#{inspect(__MODULE__)}: Error: \#{inspect(error)}")
      end
    """
  end

  defp balance_updated_projection do
    """
      defp project_balance_updated(event_data) do
        kwargs = Map.get(event_data, :kwargs, %{})

        home_id = kwargs["home_id"]
        energy_bought_kwh = kwargs["energy_bought_kwh"] || 0.0
        energy_sold_kwh = kwargs["energy_sold_kwh"] || 0.0
        net_balance_kwh = kwargs["net_balance_kwh"] || 0.0
        cost_paid = kwargs["cost_paid"] || 0.0
        revenue_received = kwargs["revenue_received"] || 0.0
        net_cost = kwargs["net_cost"] || 0.0
        simulation_time = parse_datetime(kwargs["simulation_time"])

        Repo.insert!(
          %HomeState{home_id: home_id},
          on_conflict: [
            set: [
              energy_bought_kwh: energy_bought_kwh,
              energy_sold_kwh: energy_sold_kwh,
              net_balance_kwh: net_balance_kwh,
              cost_paid: cost_paid,
              revenue_received: revenue_received,
              net_cost: net_cost,
              last_event_at: simulation_time,
              updated_at: DateTime.utc_now()
            ]
          ],
          conflict_target: :home_id
        )
      rescue
        error ->
          Logger.error("#{inspect(__MODULE__)}: Error: \#{inspect(error)}")
      end
    """
  end

  defp contract_proposed_projection do
    """
      defp project_market_contract_proposed(event_data) do
        kwargs = Map.get(event_data, :kwargs, %{})

        contract_id = kwargs["contract_id"]
        home_id = kwargs["home_id"]
        provider_id = kwargs["provider_id"]
        simulation_time = parse_datetime(kwargs["simulation_time"])

        Repo.insert!(%ContractEvent{
          contract_id: contract_id,
          home_id: home_id,
          provider_id: provider_id,
          event_type: "proposed",
          simulation_time: simulation_time,
          day_buy_price: kwargs["day_buy_price"],
          night_buy_price: kwargs["night_buy_price"],
          day_sell_price: kwargs["day_sell_price"],
          night_sell_price: kwargs["night_sell_price"],
          switching_discount: kwargs["switching_discount"]
        })
      rescue
        error ->
          Logger.error("#{inspect(__MODULE__)}: Error: \#{inspect(error)}")
      end
    """
  end

  defp contract_confirmed_projection do
    """
      defp project_market_contract_confirmed(event_data) do
        kwargs = Map.get(event_data, :kwargs, %{})

        home_id = kwargs["home_id"]
        provider_id = kwargs["provider_id"]
        contract_id = kwargs["contract_id"]
        simulation_time = parse_datetime(kwargs["simulation_time"])

        # Update home state with new contract
        Repo.insert!(
          %HomeState{home_id: home_id},
          on_conflict: [
            set: [
              provider_id: provider_id,
              contract_id: contract_id,
              contract_expires_at: parse_datetime(kwargs["end_date"]),
              last_event_at: simulation_time,
              updated_at: DateTime.utc_now()
            ]
          ],
          conflict_target: :home_id
        )

        # Insert contract event
        Repo.insert!(%ContractEvent{
          contract_id: contract_id,
          home_id: home_id,
          provider_id: provider_id,
          event_type: "confirmed",
          simulation_time: simulation_time,
          start_date: parse_datetime(kwargs["start_date"]),
          end_date: parse_datetime(kwargs["end_date"]),
          day_buy_price: kwargs["day_buy_price"],
          night_buy_price: kwargs["night_buy_price"],
          day_sell_price: kwargs["day_sell_price"],
          night_sell_price: kwargs["night_sell_price"],
          switching_discount: kwargs["switching_discount"]
        })
      rescue
        error ->
          Logger.error("#{inspect(__MODULE__)}: Error: \#{inspect(error)}")
      end
    """
  end

  defp contract_rejected_projection do
    """
      defp project_market_contract_rejected(event_data) do
        kwargs = Map.get(event_data, :kwargs, %{})

        contract_id = kwargs["contract_id"]
        home_id = kwargs["home_id"]
        provider_id = kwargs["provider_id"]
        simulation_time = parse_datetime(kwargs["simulation_time"])

        Repo.insert!(%ContractEvent{
          contract_id: contract_id,
          home_id: home_id,
          provider_id: provider_id,
          event_type: "rejected",
          simulation_time: simulation_time,
          switch_reason: kwargs["reason"]
        })
      rescue
        error ->
          Logger.error("#{inspect(__MODULE__)}: Error: \#{inspect(error)}")
      end
    """
  end

  defp contract_expired_projection do
    """
      defp project_market_contract_expired(event_data) do
        kwargs = Map.get(event_data, :kwargs, %{})

        contract_id = kwargs["contract_id"]
        home_id = kwargs["home_id"]
        provider_id = kwargs["provider_id"]
        simulation_time = parse_datetime(kwargs["simulation_time"])

        Repo.insert!(%ContractEvent{
          contract_id: contract_id,
          home_id: home_id,
          provider_id: provider_id,
          event_type: "expired",
          simulation_time: simulation_time
        })
      rescue
        error ->
          Logger.error("#{inspect(__MODULE__)}: Error: \#{inspect(error)}")
      end
    """
  end

  defp trade_executed_projection do
    """
      defp project_market_trade_executed(event_data) do
        kwargs = Map.get(event_data, :kwargs, %{})

        home_id = kwargs["home_id"]
        provider_id = kwargs["provider_id"]
        contract_id = kwargs["contract_id"]
        type = String.to_atom(kwargs["type"] || "buy")
        kwh = kwargs["kwh"] || 0.0
        price_per_kwh = kwargs["price_per_kwh"] || 0.0
        total = kwargs["total"] || 0.0
        is_day = kwargs["is_day"] || true
        simulation_time = parse_datetime(kwargs["simulation_time"])

        {import_kwh, export_kwh, import_cost, export_revenue} =
          case type do
            :buy -> {kwh, 0.0, total, 0.0}
            :sell -> {0.0, kwh, 0.0, total}
          end

        Repo.insert!(
          %EnergyTrade{
            home_id: home_id,
            provider_id: provider_id,
            contract_id: contract_id,
            simulation_time: simulation_time,
            simulation_hour: simulation_time.hour,
            grid_import_kwh: import_kwh,
            grid_export_kwh: export_kwh,
            import_price_per_kwh: if(type == :buy, do: price_per_kwh, else: nil),
            export_price_per_kwh: if(type == :sell, do: price_per_kwh, else: nil),
            is_day: is_day,
            import_cost: import_cost,
            export_revenue: export_revenue,
            net_cost: import_cost - export_revenue,
            recorded_at: DateTime.utc_now()
          },
          on_conflict: :nothing,
          conflict_target: [:home_id, :simulation_time]
        )
      rescue
        error ->
          Logger.error("#{inspect(__MODULE__)}: Error: \#{inspect(error)}")
      end
    """
  end

  defp savings_realized_projection do
    """
      defp project_market_savings_realized(event_data) do
        kwargs = Map.get(event_data, :kwargs, %{})

        home_id = kwargs["home_id"]
        gross_savings = kwargs["gross_savings"] || 0.0
        commission = kwargs["cortexiq_commission"] || 0.0
        net_savings = kwargs["net_savings_to_customer"] || 0.0
        simulation_time = parse_datetime(kwargs["simulation_time"])

        # Update home state with cumulative savings
        Repo.insert!(
          %HomeState{home_id: home_id},
          on_conflict: [
            set: [
              cortexiq_total_commission: commission,
              cortexiq_total_savings: gross_savings,
              cortexiq_net_savings: net_savings,
              last_event_at: simulation_time,
              updated_at: DateTime.utc_now()
            ]
          ],
          conflict_target: :home_id
        )

        # Update system stats
        from(s in SystemStats, where: s.id == 1)
        |> Repo.update_all(
          inc: [
            cortexiq_total_commission: commission,
            cortexiq_total_savings: gross_savings,
            cortexiq_net_savings: net_savings
          ],
          set: [updated_at: DateTime.utc_now()]
        )
      rescue
        error ->
          Logger.error("#{inspect(__MODULE__)}: Error: \#{inspect(error)}")
      end
    """
  end

  defp spot_price_updated_projection do
    """
      defp project_market_spot_price_updated(event_data) do
        kwargs = Map.get(event_data, :kwargs, %{})

        provider_id = kwargs["provider_id"]
        buy_price = kwargs["buy_price"]
        sell_price = kwargs["sell_price"]
        simulation_time = parse_datetime(kwargs["simulation_time"])

        Repo.insert!(
          %ProviderState{provider_id: provider_id},
          on_conflict: [
            set: [
              spot_buy_price: buy_price,
              spot_sell_price: sell_price,
              last_event_at: simulation_time,
              updated_at: DateTime.utc_now()
            ]
          ],
          conflict_target: :provider_id
        )
      rescue
        error ->
          Logger.error("#{inspect(__MODULE__)}: Error: \#{inspect(error)}")
      end
    """
  end

  defp arbitrage_profit_projection do
    """
      defp project_arbitrage_profit_realized(event_data) do
        kwargs = Map.get(event_data, :kwargs, %{})

        home_id = kwargs["home_id"]
        profit = kwargs["profit"] || 0.0
        simulation_time = parse_datetime(kwargs["simulation_time"])

        # Could create separate arbitrage_profits table or add to home_state
        # For now, just log it
        Logger.info("Arbitrage profit realized: \#{home_id} = $\#{profit}")
      rescue
        error ->
          Logger.error("#{inspect(__MODULE__)}: Error: \#{inspect(error)}")
      end
    """
  end

  defp simulation_reset_projection do
    """
      defp project_simulation_reset(_event_data) do
        # Clear all projection state
        Logger.warning("Simulation reset - clearing all projection state")

        # Truncate all tables
        Repo.query!("TRUNCATE home_states CASCADE")
        Repo.query!("TRUNCATE provider_states CASCADE")
        Repo.query!("TRUNCATE energy_events CASCADE")
        Repo.query!("TRUNCATE energy_trades CASCADE")
        Repo.query!("TRUNCATE contract_events CASCADE")
        Repo.query!("TRUNCATE contract_switches CASCADE")

        # Reset system stats
        Repo.insert!(
          %SystemStats{id: 1},
          on_conflict: [
            set: [
              simulation_time: nil,
              simulation_speed: 105_120,
              homes_connected_count: 0,
              contract_switches_count: 0,
              cortexiq_total_commission: 0.0,
              cortexiq_total_savings: 0.0,
              cortexiq_net_savings: 0.0,
              updated_at: DateTime.utc_now()
            ]
          ],
          conflict_target: :id
        )

        Logger.info("✓ Simulation state reset complete")
      rescue
        error ->
          Logger.error("#{inspect(__MODULE__)}: Error: \#{inspect(error)}")
      end
    """
  end
end

# Run the generator
VerticalSliceGenerator.run()
