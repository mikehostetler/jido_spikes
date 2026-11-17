defmodule Section9.Demo do
  @moduledoc "Convenience entry points for the repeatable local demonstration."

  def reset do
    baseline = Section9.Fixture.baseline()
    :ok = Section9.Ledger.reset_demo(baseline: baseline)
    :ok = Section9.SkillPackage.load_all()
    Section9.Fixture.reset_workspace()
    %{baseline: baseline, snapshot: Section9.Ledger.snapshot()}
  end

  def run_fake do
    reset()
    Section9.Team.run_auto(model_adapter: Section9.Model.Fake)
  end

  def run_local do
    reset()
    Section9.Team.run_auto(model_adapter: Section9.Model.JidoReAct)
  end

  def run_work_cell(opts \\ []) do
    contract = %{
      id: "repair-#{System.unique_integer([:positive, :monotonic])}",
      purpose: "Repair the deterministic JobServer fixture",
      done_when: "Protected checks pass and the mission closes",
      authority: :local_write,
      budget: %{pulses: 12, cost_usd: Keyword.get(opts, :cost_usd, 0)}
    }

    Section9.ViableWorkCell.run(contract, opts)
  end

  def run_human_work(opts \\ []) do
    Section9.HumanWorkSimulation.run(opts)
  end

  def interrupt_implementer do
    :ok = Section9.Actor.interrupt_next(:implementer)
    :ok
  end
end
