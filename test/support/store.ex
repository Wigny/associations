defmodule Store do
  @moduledoc """
  The store `Garage` reads through.

  Exists as a behaviour because `Mox.defmock/2` defines `MockStore` from one. `Garage` implements
  `c:Associations.list/4` by delegating to `MockStore.list/4`, so every search a test makes lands
  here, and a test says what each one answers with.
  """

  @callback list(schema :: module, fields :: [atom], values :: [[term]], args :: keyword) ::
              [struct]
end
