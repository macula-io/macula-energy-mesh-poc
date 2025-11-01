# pgAdmin 4 Deployment

PostgreSQL database administration tool for managing the CortexIQ Dashboard database.

## Access Information

- **URL**: http://pgadmin.macula.local:8080/
- **Login Email**: admin@macula.io
- **Password**: admin

## Adding CortexIQ Database Server

After logging in, add the PostgreSQL server manually:

1. Click "Add New Server" (or Object → Register → Server)
2. **General Tab**:
   - **Name**: CortexIQ Dashboard
   - **Server Group**: Macula Platform
3. **Connection Tab**:
   - **Host**: postgres.macula-hub.svc.cluster.local (or postgres.macula.local)
   - **Port**: 5432
   - **Maintenance database**: cortexiq_dashboard
   - **Username**: cortexiq
   - **Password**: cortexiq123
4. Click "Save"

## Database Schema

The CortexIQ database contains:

### Projection Tables (Read Models)
- `home_states` - Current state of all homes
- `provider_states` - Current state of energy providers

### Time Series Tables
- `energy_events` - Measurements (production/consumption/storage)
- `energy_trades` - Buy/sell transactions
- `contract_events` - Contract lifecycle events
- `contract_switches` - Provider switching events

### System Tables
- `system_stats` - Simulation statistics and counters

## Direct Database Access

You can also connect directly via psql or any PostgreSQL client:

```bash
psql -h postgres.macula.local -p 30432 -U cortexiq -d cortexiq_dashboard
# Password: cortexiq123
```

Or from within the cluster:
```bash
psql -h postgres.macula-hub.svc.cluster.local -p 5432 -U cortexiq -d cortexiq_dashboard
```

## Reset Database

The simulation reset button (`be.cortexiq.simulation.reset` RPC) automatically:
1. Truncates all projection and time series tables
2. Resets `system_stats` to initial values

See: `system/cortex_iq_projections/lib/cortex_iq_projections/project_simulation_reset/projector.ex`
