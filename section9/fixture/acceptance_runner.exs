candidate_path = System.fetch_env!("SECTION9_CANDIDATE")
Code.require_file(candidate_path)

ExUnit.start(autorun: false, capture_log: true)

defmodule Section9Fixture.AcceptanceTest do
  use ExUnit.Case, async: false

  alias Section9Fixture.JobServer

  setup do
    {:ok, server} = JobServer.start_link([])
    %{server: server}
  end

  test "normal result arrives once", %{server: server} do
    ref = make_ref()
    assert :ok = JobServer.start(server, ref)
    JobServer.deliver(server, ref, :done)
    assert :ok = JobServer.sync(server)
    assert_receive {:job_result, ^ref, :done}

    JobServer.deliver(server, ref, :duplicate)
    assert :ok = JobServer.sync(server)
    refute_receive {:job_result, ^ref, :duplicate}, 0
  end

  test "cancel removes ownership and reports cancellation", %{server: server} do
    ref = make_ref()
    assert :ok = JobServer.start(server, ref)
    assert :ok = JobServer.cancel(server, ref)
    assert_receive {:job_cancelled, ^ref}

    JobServer.deliver(server, ref, :late)
    assert :ok = JobServer.sync(server)
    refute_receive {:job_result, ^ref, :late}, 0
  end

  test "late and duplicate deliveries do not damage later work", %{server: server} do
    canceled = make_ref()
    next = make_ref()

    assert :ok = JobServer.start(server, canceled)
    assert :ok = JobServer.cancel(server, canceled)
    assert_receive {:job_cancelled, ^canceled}

    JobServer.deliver(server, canceled, :late_one)
    JobServer.deliver(server, canceled, :late_two)
    assert :ok = JobServer.sync(server)
    refute_receive {:job_result, ^canceled, _}, 0

    assert Process.alive?(server)
    assert :ok = JobServer.start(server, next)
    JobServer.deliver(server, next, :next_done)
    assert :ok = JobServer.sync(server)
    assert_receive {:job_result, ^next, :next_done}
  end
end

result = ExUnit.run()
System.halt(if(result.failures == 0, do: 0, else: 1))
