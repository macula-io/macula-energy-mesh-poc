# Architecture Guidelines - Screaming Architecture

## Core Principle: SCREAMING ARCHITECTURE

**The intent of a module should be IMMEDIATELY clear from its filename.**

When someone opens the codebase, they should understand what the system does just by reading file names - WITHOUT opening files or reading code.

## The Problem with Generalization

### ❌ BAD: Over-Generalized (Silent Architecture)

```
lib/cortex_iq_homes/
├── subscriber_system.ex          # What does it subscribe to? Unknown!
├── publisher_system.ex            # What does it publish? Unknown!
└── subscribers/
    └── event_subscriber.ex        # What event? Unknown!
```

**Problems:**
- File names don't tell you what they do
- Requires reading code or configuration to understand
- Mental mapping required: "SubscriberSystem with event_type: :simulation_time"
- Abstractions hide business intent
- Hard to navigate large codebases

### ✅ EXCELLENT: Business-First Vertical Slicing (Screaming Architecture)

```
lib/cortex_iq_homes/
├── home_bot.ex
├── home_supervisor.ex
│
├── subscribe_simulation_time_advanced/      # SCREAMS: subscribes to simulation time!
│   ├── system.ex                            # Supervises WAMP client + subscriber
│   └── subscriber.ex                        # Handles subscription logic
│
├── subscribe_contract_proposed/             # SCREAMS: subscribes to contract offers!
│   ├── system.ex
│   └── subscriber.ex
│
├── publish_home_measured/                   # SCREAMS: publishes measurements!
│   ├── system.ex                            # Supervises WAMP client + publisher
│   └── publisher.ex                         # Handles publication logic
│
└── publish_contract_switched/               # SCREAMS: publishes contract switches!
    ├── system.ex
    └── publisher.ex
```

**Benefits:**
- **Business capability is primary organization** (not technical patterns!)
- Immediate understanding from folder name
- No mental mapping needed
- Complete vertical slice per folder
- Easy to add/remove capabilities (just add/delete folder)
- Self-contained (system + subscriber/publisher together)
- Self-documenting architecture

## Naming Conventions for Business-First Vertical Slices

### Folder Names - The Business Capability

Pattern: `{direction}_{event_name}/`

**Subscriber Folders (Inbound from WAMP → HomeBot):**
- `subscribe_simulation_time_advanced/`
- `subscribe_contract_proposed/`
- `subscribe_spot_price_updated/`
- `subscribe_contract_confirmed/`
- `subscribe_contract_rejected/`

**Publisher Folders (Outbound from HomeBot → WAMP):**
- `publish_home_measured/`
- `publish_home_initialized/`
- `publish_home_connected/`
- `publish_home_disconnected/`
- `publish_contract_signed/`
- `publish_contract_switched/`
- `publish_contract_expired/`
- `publish_trade_executed/`
- `publish_arbitrage_profit/`
- `publish_balance_updated/`

### Module Names Within Each Slice

**System Module** (always named `System`):
```elixir
# In subscribe_simulation_time_advanced/system.ex
defmodule CortexIqHomes.SubscribeSimulationTimeAdvanced.System do
  # Supervises WAMP client + Subscriber
end

# In publish_home_measured/system.ex
defmodule CortexIqHomes.PublishHomeMeasured.System do
  # Supervises WAMP client + Publisher
end
```

**Subscriber/Publisher Module** (always named `Subscriber` or `Publisher`):
```elixir
# In subscribe_simulation_time_advanced/subscriber.ex
defmodule CortexIqHomes.SubscribeSimulationTimeAdvanced.Subscriber do
  # Handles WAMP subscription logic
end

# In publish_home_measured/publisher.ex
defmodule CortexIqHomes.PublishHomeMeasured.Publisher do
  # Handles WAMP publication logic
end
```

**Key Insight**: The folder name IS the business capability. The files within are ALWAYS named `system.ex` and `subscriber.ex`/`publisher.ex`. No repetition!

## Code Structure Per Vertical Slice

Each vertical slice is COMPLETELY SELF-CONTAINED:

```elixir
# subscribe_simulation_time_advanced/system.ex
defmodule CortexIqHomes.SubscribeSimulationTimeAdvanced.System do
  @moduledoc """
  Vertical slice system for simulation.time_advanced events.

  Supervises:
  - WAMP client (unique to this slice)
  - Subscriber (handles WAMP events)

  When WAMP client crashes, subscriber restarts (:rest_for_one)
  """
  use Supervisor

  alias CortexIqHomes.SubscribeSimulationTimeAdvanced.Subscriber

  def start_link(opts) do
    home_id = Keyword.fetch!(opts, :home_id)
    Supervisor.start_link(__MODULE__, opts, name: via_tuple(home_id))
  end

  @impl true
  def init(opts) do
    home_id = Keyword.fetch!(opts, :home_id)
    realm = Keyword.get(opts, :realm)
    bondy_url = Keyword.get(opts, :bondy_url)

    wamp_client_name = :"wamp_sub_sim_time_#{String.slice(home_id, 0..10)}"

    children = [
      # WAMP Client (unique to this vertical slice)
      {MaculaSdk.Wamp.Client, [url: bondy_url, realm: realm, name: wamp_client_name]},
      # Subscriber
      {Subscriber, [wamp_client: wamp_client_name, home_id: home_id]}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp via_tuple(home_id) do
    {:via, Registry, {CortexIqHomes.Registry, {__MODULE__, home_id}}}
  end
end
```

**NO generic base classes. NO shared logic that obscures intent.**

Each vertical slice is fully explicit and self-contained.

## Supervision Tree Should Scream Too

```elixir
# HomeSupervisor - BEFORE (Silent - Technical Grouping)
children = [
  {SubscriberSystem, event_type: :simulation_time, ...},  # What? Have to read config
  {SubscriberSystem, event_type: :contract_offer, ...},   # What? Have to read config
  {PublisherSystem, publisher_type: :measurement, ...}    # What? Have to read config
]

# HomeSupervisor - AFTER (Screaming - Business Capabilities!)
children = [
  {CortexIqHomes.SubscribeSimulationTimeAdvanced.System, home_id: home_id, ...},
  {CortexIqHomes.SubscribeContractProposed.System, home_id: home_id, ...},
  {CortexIqHomes.PublishHomeMeasured.System, home_id: home_id, ...}
]
```

When you read the supervision tree, you IMMEDIATELY know:
1. **WHAT** business capabilities exist for a home
2. **DIRECTION** (Subscribe = inbound, Publish = outbound)
3. **EVENT** being handled

No configuration reading required!

## When to Use Generalization

**ONLY when the generalization IS the business concept.**

Examples where generalization is OK:
- `EventStore` - The generic concept IS the domain model
- `Repo` - The generic concept IS the domain model
- `Cache` - The generic concept IS the domain model

Examples where generalization is BAD:
- `SubscriberSystem` - Too generic, hides business intent
- `PublisherSystem` - Too generic, hides business intent
- `Handler` - Too generic, hides business intent
- `Manager` - Too generic, hides business intent
- `Service` - Too generic, hides business intent

## Complete File Structure - Business Capabilities First!

```
lib/cortex_iq_homes/
├── home_bot.ex                                   # Coordinator (no WAMP client)
├── home_supervisor.ex                            # Supervises all systems for one home
│
├── subscribe_simulation_time_advanced/           # ← Business capability!
│   ├── system.ex                                 # Supervises WAMP + Subscriber
│   └── subscriber.ex                             # Subscription logic
│
├── subscribe_contract_proposed/                  # ← Business capability!
│   ├── system.ex
│   └── subscriber.ex
│
├── subscribe_spot_price_updated/                 # ← Business capability!
│   ├── system.ex
│   └── subscriber.ex
│
├── subscribe_contract_confirmed/                 # ← Business capability!
│   ├── system.ex
│   └── subscriber.ex
│
├── subscribe_contract_rejected/                  # ← Business capability!
│   ├── system.ex
│   └── subscriber.ex
│
├── publish_home_measured/                        # ← Business capability!
│   ├── system.ex                                 # Supervises WAMP + Publisher
│   └── publisher.ex                              # Publication logic
│
├── publish_home_initialized/                     # ← Business capability!
│   ├── system.ex
│   └── publisher.ex
│
├── publish_home_connected/                       # ← Business capability!
│   ├── system.ex
│   └── publisher.ex
│
├── publish_home_disconnected/                    # ← Business capability!
│   ├── system.ex
│   └── publisher.ex
│
├── publish_contract_signed/                      # ← Business capability!
│   ├── system.ex
│   └── publisher.ex
│
├── publish_contract_switched/                    # ← Business capability!
│   ├── system.ex
│   └── publisher.ex
│
├── publish_contract_expired/                     # ← Business capability!
│   ├── system.ex
│   └── publisher.ex
│
├── publish_trade_executed/                       # ← Business capability!
│   ├── system.ex
│   └── publisher.ex
│
├── publish_arbitrage_profit/                     # ← Business capability!
│   ├── system.ex
│   └── publisher.ex
│
└── publish_balance_updated/                      # ← Business capability!
    ├── system.ex
    └── publisher.ex
```

**When you open the codebase, you see a LIST OF BUSINESS CAPABILITIES - not technical patterns!**

**Zero technical grouping. Pure vertical slicing. Each folder is a complete, self-contained feature.**

## Key Takeaway

**If you can't understand what a module does from its filename, the name is wrong.**

Names should be:
- Specific (not generic)
- Descriptive (tells the full story)
- Domain-focused (uses business terminology)
- Complete (no abbreviations that hide meaning)

The architecture should SCREAM its intent at you.

---

## Idiomatic Elixir Coding Practices

### Core Principles

1. **Use pattern matching** - The primary control flow mechanism in Elixir
2. **Avoid `if`, `case`, `try`, `catch`, `cond`** - Use pattern matching instead
3. **Write declarative code** - Express WHAT you want, not HOW to do it
4. **Prefer tail recursion over loops** - Elixir has no loops, use recursion

### Pattern Matching Over Conditionals

#### ❌ BAD: Using `if` and `case`

```elixir
def handle_event(event_data, state) do
  if event_data.type == :measurement do
    # Handle measurement
  else
    if event_data.type == :contract do
      # Handle contract
    else
      # Handle other
    end
  end
end

# Or using case
def handle_event(event_data, state) do
  case event_data.type do
    :measurement -> # Handle measurement
    :contract -> # Handle contract
    _ -> # Handle other
  end
end
```

**Problems:**
- Nested conditionals (imperative)
- Have to extract type first
- Logic hidden inside blocks
- Not leveraging Elixir's strengths

#### ✅ GOOD: Pattern Matching on Function Heads

```elixir
# Separate function clauses - declarative!
def handle_event(%{type: :measurement} = data, state) do
  # Handle measurement
end

def handle_event(%{type: :contract} = data, state) do
  # Handle contract
end

def handle_event(_data, state) do
  # Handle other
end
```

**Benefits:**
- Declarative (WHAT, not HOW)
- Self-documenting (each clause tells a story)
- Compiler-optimized pattern matching
- Easy to add new cases (just add function clause)

### Real Example: WAMP Event Routing

#### ❌ BAD: String matching with `cond`

```elixir
def handle_info({:wamp_event, topic, _args, kwargs, _details}, state) do
  cond do
    String.contains?(topic, ".contract_proposed") ->
      # handle contract proposed
    String.contains?(topic, ".spot_price_updated") ->
      # handle spot price
    String.ends_with?(topic, ".contract_confirmed") ->
      # handle contract confirmed
    true ->
      # unknown
  end
end
```

#### ✅ GOOD: Pattern matching on exact topics

```elixir
# Crystal clear - each function clause is self-documenting
def handle_info({:wamp_event, "be.cortexiq.market.contract_proposed", _args, kwargs, _details}, state) do
  # handle contract proposed
end

def handle_info({:wamp_event, "be.cortexiq.market.spot_price_updated", _args, kwargs, _details}, state) do
  # handle spot price
end

def handle_info({:wamp_event, "be.cortexiq.market.contract_confirmed", _args, kwargs, _details}, state) do
  # handle contract confirmed
end

def handle_info({:wamp_event, topic, _args, _kwargs, _details}, state) do
  Logger.warning("Unknown WAMP event: #{topic}")
  {:noreply, state}
end
```

### Tail Recursion Over Loops

Elixir has **no loops** - use recursion instead.

#### ❌ BAD: Trying to use loops (doesn't exist in Elixir!)

```elixir
# This is pseudo-code - loops don't exist in Elixir
def process_items(items) do
  for item in items do
    process(item)
  end
end
```

#### ✅ GOOD: Tail recursion or Enum functions

```elixir
# Option 1: Using Enum (most common)
def process_items(items) do
  Enum.map(items, &process/1)
end

# Option 2: Tail recursion (when you need more control)
def process_items(items), do: process_items(items, [])

defp process_items([], acc), do: Enum.reverse(acc)

defp process_items([item | rest], acc) do
  result = process(item)
  process_items(rest, [result | acc])
end
```

### Declarative Over Imperative

#### ❌ BAD: Imperative (telling HOW)

```elixir
def calculate_total(orders) do
  total = 0
  for order in orders do
    total = total + order.amount
  end
  total
end
```

#### ✅ GOOD: Declarative (expressing WHAT)

```elixir
def calculate_total(orders) do
  orders
  |> Enum.map(& &1.amount)
  |> Enum.sum()
end

# Or even simpler
def calculate_total(orders) do
  Enum.sum_by(orders, & &1.amount)
end
```

### Guards Over Conditionals

#### ❌ BAD: Using `if` inside function

```elixir
def process_home(home, state) do
  if home.battery_capacity > 10 do
    # large battery logic
  else
    # small battery logic
  end
end
```

#### ✅ GOOD: Pattern matching with guards

```elixir
def process_home(%{battery_capacity: capacity} = home, state) when capacity > 10 do
  # large battery logic
end

def process_home(home, state) do
  # small battery logic
end
```

### With Statement for Complex Pipelines (Sparingly)

When you have multiple operations that can fail, `with` is acceptable:

```elixir
def create_contract(home_id, offer_id) do
  with {:ok, home} <- fetch_home(home_id),
       {:ok, offer} <- fetch_offer(offer_id),
       {:ok, contract} <- validate_contract(home, offer),
       {:ok, _} <- save_contract(contract) do
    {:ok, contract}
  else
    {:error, reason} -> {:error, reason}
  end
end
```

But prefer pattern matching when possible:

```elixir
def create_contract(home_id, offer_id) do
  home_id
  |> fetch_home()
  |> then(&fetch_offer(offer_id, &1))
  |> then(&validate_contract/1)
  |> then(&save_contract/1)
end
```

### Summary

**DO:**
- ✅ Use pattern matching on function heads
- ✅ Write separate function clauses for different cases
- ✅ Use guards for simple conditions
- ✅ Use Enum functions for collection operations
- ✅ Use tail recursion when needed
- ✅ Write declarative code (express WHAT)
- ✅ Use `with` for complex error-handling pipelines (sparingly)

**DON'T:**
- ❌ Use `if` (pattern match instead)
- ❌ Use `case` (pattern match instead)
- ❌ Use `cond` (pattern match instead)
- ❌ Use `try/catch` (use pattern matching on {:ok, _} / {:error, _})
- ❌ Write imperative code (avoid HOW, express WHAT)
- ❌ Nest conditionals
- ❌ Try to use loops (use Enum or recursion)

**Remember:** Elixir is a functional language. Embrace pattern matching, immutability, and declarative style!

---

## Testing Requirements - Every Module Must Have Tests

**CRITICAL: No module is complete without passing tests.**

### Core Principle

Every module MUST have:
1. A corresponding test file
2. Tests that PASS
3. Meaningful test coverage of public functions

**No exceptions.** If you create a module, you create tests.

### Test File Structure

Tests mirror the source structure:

```
lib/cortex_iq_homes/
├── subscribe_simulation_time_advanced/
│   ├── system.ex
│   └── subscriber.ex
│
test/cortex_iq_homes/
├── subscribe_simulation_time_advanced/
│   ├── system_test.exs
│   └── subscriber_test.exs
```

### Naming Convention

**Source file**: `lib/cortex_iq_homes/publish_home_measured/publisher.ex`
**Test file**: `test/cortex_iq_homes/publish_home_measured/publisher_test.exs`

**Module**: `CortexIqHomes.PublishHomeMeasured.Publisher`
**Test module**: `CortexIqHomes.PublishHomeMeasured.PublisherTest`

### What to Test

#### System Modules

Test supervision tree setup:
- Children start in correct order
- Correct supervision strategy (:rest_for_one)
- WAMP client and subscriber/publisher both start
- Proper naming via Registry

```elixir
defmodule CortexIqHomes.SubscribeSimulationTimeAdvanced.SystemTest do
  use ExUnit.Case, async: true

  alias CortexIqHomes.SubscribeSimulationTimeAdvanced.System

  describe "init/1" do
    test "starts WAMP client and subscriber with correct strategy" do
      opts = [home_id: "test-home", realm: "test.realm", bondy_url: "ws://localhost:18080/ws"]

      assert {:ok, {supervisor_spec, children}} = System.init(opts)
      assert supervisor_spec == :one_for_one

      assert length(children) == 2
      assert Enum.any?(children, &match?(%{id: :wamp_client}, &1))
      assert Enum.any?(children, &match?({_, _}, &1))
    end
  end
end
```

#### Subscriber Modules

Test subscription logic:
- Subscribes to correct topic
- Parses event data correctly
- Sends correct message to HomeBot
- Handles missing HomeBot gracefully

```elixir
defmodule CortexIqHomes.SubscribeSimulationTimeAdvanced.SubscriberTest do
  use ExUnit.Case, async: true

  alias CortexIqHomes.SubscribeSimulationTimeAdvanced.Subscriber

  describe "handle_info/2 with :event" do
    test "parses simulation time and sends to HomeBot" do
      state = %{wamp_client: :test_client, home_id: "test-home"}

      event_data = %{
        kwargs: %{"simulation_time" => "2025-01-15T10:30:00Z"}
      }

      # Mock HomeBot.whereis to return test process
      # Then verify message sent

      assert {:noreply, ^state} = Subscriber.handle_info({:event, event_data}, state)
    end

    test "handles missing simulation time gracefully" do
      state = %{wamp_client: :test_client, home_id: "test-home"}
      event_data = %{kwargs: %{}}

      assert {:noreply, ^state} = Subscriber.handle_info({:event, event_data}, state)
    end
  end
end
```

#### Publisher Modules

Test publication logic:
- publish/2 function works correctly
- whereis/1 finds publisher via Registry
- handle_info publishes to correct topic
- Handles WAMP errors gracefully

```elixir
defmodule CortexIqHomes.PublishHomeMeasured.PublisherTest do
  use ExUnit.Case, async: true

  alias CortexIqHomes.PublishHomeMeasured.Publisher

  describe "publish/2" do
    test "sends message to publisher process" do
      # Setup publisher in Registry
      # Call publish/2
      # Verify message sent
    end

    test "handles missing publisher gracefully" do
      Publisher.publish("nonexistent-home", %{})
      # Should log warning but not crash
    end
  end

  describe "handle_info/2 with :publish" do
    test "publishes data to WAMP topic" do
      state = %{wamp_client: :test_client, home_id: "test-home"}
      data = %{power_w: 1000}

      # Mock WAMP client
      # Verify correct topic and data

      assert {:noreply, ^state} = Publisher.handle_info({:publish, data}, state)
    end
  end
end
```

### Test Execution

**Run all tests**:
```bash
mix test
```

**Run specific test file**:
```bash
mix test test/cortex_iq_homes/subscribe_simulation_time_advanced/subscriber_test.exs
```

**Run with coverage**:
```bash
mix test --cover
```

### Minimum Requirements

- ✅ **All tests pass** - No failures, no skipped tests
- ✅ **Public functions tested** - Every public function has at least one test
- ✅ **Edge cases covered** - Test nil values, errors, boundary conditions
- ✅ **Pattern matching tested** - Verify different function clauses work correctly

### When to Write Tests

**BEFORE pushing code:**
1. Write module
2. Write tests
3. Verify tests pass
4. Commit

**NOT after the fact.** Tests are part of the module, not an afterthought.

### Testing Vertical Slices

Each vertical slice folder should have:
```
lib/cortex_iq_homes/subscribe_simulation_time_advanced/
├── system.ex                    # Supervision
└── subscriber.ex                # Business logic

test/cortex_iq_homes/subscribe_simulation_time_advanced/
├── system_test.exs              # Test supervision
└── subscriber_test.exs          # Test business logic
```

### Key Takeaway

**If it doesn't have tests, it's not done.**

Tests are not optional. They are part of the definition of "complete code."
