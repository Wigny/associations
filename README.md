# Associations

Declarative associations between plain structs, loaded in batches.

Structs that come from anywhere (an API client, an ETS table, a context function) have no associations of their own. `Associations` lets a module declare how they relate and how to fetch them, then reads those declarations in `load/2` and `load_many/2`.

```elixir
defmodule Garage do
  use Associations

  @impl true
  def fetch(schema, fields, values) do
    Store.list_by(schema, fields, values)
  end

  association Car do
    belongs_to :owner, Person
  end

  association Person do
    has_many :cars, Car, foreign_key: :owner_id
  end
end
```

```elixir
Garage.load(car, :owner)
#=> %Person{id: 1}

Garage.load_many([person, dealer], :cars)
#=> [{%Person{id: 1}, [%Car{id: 1}, %Car{id: 2}]}, {%Dealer{code: "AAA"}, [%Car{id: 1}]}]
```

The `Associations` documentation covers association paths, the `Associations.belongs_to/3`,
`Associations.has_many/3` and `Associations.many_to_many/3` declarations, and the
`c:Associations.fetch/3` callback every search goes through.

## Installation

Add `associations` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:associations, github: "Wigny/associations"}
  ]
end
```
