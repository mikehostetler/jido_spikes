# Load one stage of a fictional checkout incident into the shared review Memory.
stage =
  case System.argv() do
    ["initial"] -> :initial
    ["update"] -> :update
    ["confirmed"] -> :confirmed
    _ -> raise "Usage: mix run examples/incident_review.exs initial|update|confirmed"
  end

alias Jarvis.Memories

samples = %{
  initial:
    "10:05 UTC: East checkout errors rose from 0.2% to 8% after v42 reached East. West is at 0.2%. The dashboard has no version breakdown yet. No dependency alert has arrived.",
  update:
    "10:15 UTC: Corrected dashboard: East errors are 8.1% on v42 and 8.0% on v41. West is at 0.2% on both versions. The payment provider reports elevated timeouts at its East endpoint. Traces have not yet confirmed the cause."
}

samples =
  Map.put(
    samples,
    :confirmed,
    samples.update <>
      " 10:25 UTC: The incident commander confirms v42 has already been fully rolled back. East errors remain at 8% on v41 alone. Traces confirm payment requests are timing out. No further release rollback is possible."
  )

records = [
  {"timeline",
   "10:00 UTC: Checkout v42 entered a partial rollout. Both v41 and v42 serve requests in East and West. No database migration shipped. The release can be rolled back."},
  {"response policy",
   "Above 5% errors after a reversible deploy, recommend rollback as a precaution unless comparable errors also affect the previous version. In that case, hold the rollout and investigate the shared dependency before reversing the release."},
  {"observations", samples[stage]}
]

tag = %{"demo" => "checkout-incident"}

{:ok, _} =
  Jarvis.Repo.transaction(fn ->
    existing = Memories.list_memories(namespace: "jarvis") |> Enum.filter(&(&1.metadata == tag))

    for {key, content} <- records do
      title = "Checkout incident: " <> key

      case Enum.find(existing, &(&1.title == title)) do
        nil ->
          {:ok, _} =
            Memories.remember(%{
              namespace: "jarvis",
              title: title,
              content: content,
              metadata: tag
            })

        %{content: ^content} ->
          :unchanged

        row ->
          {:ok, _} = Memories.supersede(row, %{content: content})
      end
    end
  end)

IO.puts("Checkout incident: #{stage} evidence loaded.")
