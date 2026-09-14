# Associations

Declarative associations between plain structs, loaded in batches.

Structs that come from anywhere (an API client, an ETS table, a context function) have no associations of their own. `Associations` lets a module declare how they relate and how to list them, then reads those declarations in `load/2` and `load_many/2`.

```elixir
defmodule Garage do
  use Associations

  alias Garage.{Car, Customer}

  @impl true
  def list(schema, fields, values) do
    Store.list_by(schema, fields, values)
  end

  association Car do
    belongs_to :owner, Customer
  end

  association Customer do
    has_many :cars, Car, foreign_key: :owner_id
  end
end
```

```elixir
Garage.load(car, :owner)
#=> %Customer{id: 1}

Garage.load_many([customer, dealer], :cars)
#=> [{%Customer{id: 1}, [%Car{id: 1}, %Car{id: 2}]}, {%Dealer{code: "AAA"}, [%Car{id: 1}]}]
```

See `Associations` for the full documentation.

## Installation

Add `associations` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:associations, github: "Wigny/associations"}
  ]
end
```
