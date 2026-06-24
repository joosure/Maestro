defmodule SymphonyElixir.Storage.TableCatalog.Source do
  @moduledoc """
  Source behaviour for table-catalog contract registration.

  A source is an application-assembly boundary: it returns trusted storage
  contract modules without making `Storage.TableCatalog` compile-depend on the
  domains that own those contracts.
  """

  @callback entry_modules(keyword()) :: [module()]
end
