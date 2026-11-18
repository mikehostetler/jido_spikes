defmodule Kura.Maintenance.Review do
  @moduledoc "Handles Cedar's maintenance handoff to the Review cell using local evidence."

  alias Kura.Cell.{Catalog, Control}
  alias Kura.Playbooks.Fixtures

  def inspect_failure(
        owner_id,
        cell_id,
        case_id,
        %{"status" => "failed", "head" => head} = fixture,
        correlation
      ) do
    with {:ok, owner} <- Catalog.fetch(owner_id),
         {:ok, owner_receipt} <- Control.authorize(owner, correlation["wait_id"] || case_id),
         {:ok, cell} <- Catalog.fetch(cell_id),
         {:ok, receipt} <- Control.authorize(cell, case_id) do
      finding =
        if fixture["assertion_complete"] == false,
          do: Fixtures.review_finding(),
          else: fixture["evidence"]

      {:ok, owner_receipt,
       Map.merge(correlation, %{"head" => head, "receipt" => receipt, "finding" => finding})}
    end
  end
end
