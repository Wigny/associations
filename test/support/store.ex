defmodule Store do
  @moduledoc """
  The store `Garage` fetches through.

  Exists as a behaviour because `Mox.defmock/2` defines `MockStore` from one. `Garage` implements
  `c:Associations.fetch/3` by delegating to `MockStore.list/3`, so every search a test makes lands
  here, and a test says what each one answers with.
  """

  @callback list(schema :: module, fields :: [atom], values :: [[term]]) :: [struct]
end
