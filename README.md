# Associations

Declarative associations between plain structs, loaded in batches.

Structs that come from anywhere (an API client, an ETS table, a context function) have no associations of their own. `Associations` lets a module declare how they relate and how to fetch them, then reads those declarations in `load/2` and `load_many/2`.

```elixir
defmodule Relations do
  use Associations

  @impl true
  def fetch(schema, searches) do
    Map.new(searches, fn search -> {search, Garage.list_by(schema, search)} end)
  end

  association Car do
    belongs_to :owner, Person
    belongs_to :dealer, Dealer, foreign_key: :dealer_code, references: :code
  end

  association Person do
    has_many :cars, Car, foreign_key: :owner_id
    has_many :invoices, Invoice
  end
end
```

```elixir
Relations.load(person, :cars)
#=> [%Car{id: 1, owner_id: 1}, %Car{id: 2, owner_id: 1}]

Relations.load(car, :owner)
#=> %Person{id: 1}
```

A `belongs_to` association returns a single record, or `nil` when none matches; it raises when more than one does. A `has_many` association returns a list.

## Loading without N+1

`load/2` in a loop searches once per record. `load_many/2` searches for all of them at once, returning a `{record, records}` pair per record, in the order they were given:

```elixir
Relations.load_many([person, dealer], :cars)
#=> [{%Person{id: 1}, [%Car{id: 1}, %Car{id: 2}]}, {%Dealer{code: "AAA"}, [%Car{id: 1}]}]
```

The records may be of different schemas, as above, as long as each declares the association. Records looking for the same thing are searched for once.

## Paths

Both functions take a path of associations as well as a single one, walking one association of the records the one before it found, the way `get_in/2` walks a nested map:

```elixir
Relations.load(person, [:cars, :dealer])
#=> [%Dealer{code: "AAA"}]
```

Every hop is searched for in its own batch, no matter how many records reached it, so the path above is two searches whether it starts from one person or a hundred. The records the last hop found are returned without repeats, so the dealer who sold both cars is listed once.

A path returns a single record only when every association along it is a `belongs_to`; one `has_many` or `many_to_many` anywhere in it makes the result a list, as above. The records the hops in between found are not returned, so a path tells you which records it ended on, not which of the records before them led there.

## Fetching

Every association goes through the single `fetch/2` callback. It receives the schema being loaded and the searches batched for it, and returns a map pairing each search with the records matching it. A search is a map of fields and values, such as `%{owner_id: 1}`, so the callback has to handle each schema it may be asked for.

## Installation

Add `associations` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:associations, github: "Wigny/associations"}
  ]
end
```
