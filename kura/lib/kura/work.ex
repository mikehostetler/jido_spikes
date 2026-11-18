defmodule Kura.Work do
  @moduledoc "The Ash domain for work cell resources and actions."

  use Ash.Domain, extensions: [AshJido]

  resources do
    resource Kura.Work.Entry
    resource Kura.Work.MaintenanceCase
  end
end
