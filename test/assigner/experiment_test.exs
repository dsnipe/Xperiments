defmodule Xperiments.Assigner.ExperimentTest do
  use Xperiments.AssignCase
  alias Xperiments.Assigner.{ExperimentSupervisor, Experiment}

  setup do
    app = insert(:application, name: "web")
    excluded_exp = insert(:experiment, application: app)
    exp =
      insert(:experiment, state: "running", max_users: 5, exclusions: [excluded_exp], rules: Xperiments.Factory.rules_1)
    exp = Map.merge(exp, %{exclusions: Xperiments.Experiments.Exclusion.for_experiment(exp.id)})
    ExperimentSupervisor.start_experiment(exp)
    [exp: exp, excluded_exp: excluded_exp]
  end

  test "get an exclusions list of a specific experiment", context do
    exclusions = context.exp.exclusions
    assert length(exclusions) == 1
    exc_list = Experiment.get_exclusions_list(context.exp.id)
    assert length(exc_list) == 1
    assert exc_list == exclusions
  end

  test "experiment return a randomly (according to an allocation) assigned result" do
    exp = Xperiments.Factory.experiment_with_balanced_variants()
    ExperimentSupervisor.start_experiment(exp)
    variant = Experiment.get_random_variant(exp.id)
    assert is_map(variant)
  end

  test "correctly assignes of variants based for many requests based on variants allocations" do
    exp = Xperiments.Factory.experiment_with_balanced_variants()
    ExperimentSupervisor.start_experiment(exp)
    allocations = for _i <- 0..10000 do
      exp = Experiment.get_random_variant(exp.id)
      exp.variant.allocation
    end

    assert_in_delta Enum.count(allocations, &(&1 == 50)), 5000, 200
    assert_in_delta Enum.count(allocations, &(&1 == 30)), 3000, 200
    assert_in_delta Enum.count(allocations, &(&1 == 20)), 2000, 200
  end

  test "check rules correctly", context do
    eid = context.exp.id
    bad_segment_1 = %{"type" => "plus"}
    bad_segment_2 = %{"lang" => "de"}
    bad_segment_3 = %{"lang" => "ru", "system" => "windows"}
    bad_segment_4 = %{"system" => "osx"}
    refute Experiment.accept_segments?(eid, bad_segment_1)
    refute Experiment.accept_segments?(eid, bad_segment_2)
    refute Experiment.accept_segments?(eid, bad_segment_3)
    refute Experiment.accept_segments?(eid, bad_segment_4)

    good_segment = %{"lang" => "ru", "system" => "osx"}
    assert Experiment.accept_segments?(eid, good_segment)
  end

  test "match regex rules" do
    match_rule = %{
      parameter: "user_ids",
      operator: "=~",
      value: "^[\\d,]+\\d$",
      type: "regex"}
    exp =
      insert(:experiment, state: "running", max_users: 5, exclusions: [], rules: [match_rule])
    ExperimentSupervisor.start_experiment(exp)

    match_segment = %{"user_ids" => "1,2,140,1005"}

    assert Experiment.accept_segments?(exp.id, match_segment)
  end

  test "not allow to run an out-of-date experiment" do
    exp = insert(:experiment, state: "running", end_date: DateTime.utc_now())
    {result, _} = Experiment.init(exp)
    assert result == :stop
  end

  test "automaticly shutdown an experiment on the end_date" do
    exp = insert(:experiment, state: "running", end_date: DateTime.utc_now() |> Timex.shift(milliseconds: 80))
    {:ok, pid} = ExperimentSupervisor.start_experiment(exp)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end

  test "that an experiment start checker works" do
    exp = insert(:experiment, state: "running", start_date: Timex.now |> Timex.shift(days: 1))
    ExperimentSupervisor.start_experiment(exp)
    refute Experiment.is_started?(exp.id)
  end

  test "adding of an exclusion", context do
    new_exp = insert(:experiment, state: "running", start_date: Timex.now |> Timex.shift(days: 1), exclusions: [context.exp])
    Experiment.add_exclusion(context.exp.id, [new_exp.id])
    assert length(Experiment.get_exclusions_list(context.exp.id)) == 2
  end

  test "removing of an exclusion", context do
    assert length(Experiment.get_exclusions_list(context.exp.id)) == 1
    Experiment.remove_exclusion(context.exp.id, context.excluded_exp.id)
    assert length(Experiment.get_exclusions_list(context.exp.id)) == 0
  end

  test "making a default statistics if it is not set", context do
    {:ok, state} = Experiment.init(context.exp)
    assert state.statistics == %{common_impression: 0, variants_impression: %{}}
  end

  test "incrementing of impression", context do
    {:ok, state} = Experiment.init(context.exp)
    {:noreply, new_state} = Experiment.handle_cast({:inc_impression, "any_var_id"}, state)
    assert new_state.statistics == %{common_impression: 1,
                                     variants_impression: %{"any_var_id" => 1}}
    {:noreply, new_state} = Experiment.handle_cast({:inc_impression, "other_var"}, new_state)
    assert new_state.statistics == %{common_impression: 2,
                                     variants_impression: %{"any_var_id" => 1, "other_var" => 1}}
  end

  test "statistics saves to DB after treshhold impressions", context do
    {:ok, state} = Experiment.init(context.exp)
    db_exp = Xperiments.Repo.get!(Xperiments.Experiments.Experiment, context.exp.id)
    assert db_exp.statistics == nil
    Enum.scan(0..5, state, fn _, state ->
      {:noreply, new_state} = Experiment.handle_cast({:inc_impression, "any_var_id"}, state)
      new_state
    end)
    :timer.sleep(100) # wait for an async db query
    db_exp = Xperiments.Repo.get!(Xperiments.Experiments.Experiment, context.exp.id)
    assert db_exp.statistics ==
      %Xperiments.Experiments.Experiment.Statistics{
        common_impression: 4,
        variants_impression: %{"any_var_id" => 4}
      }
  end

  test "termination of an expeiment if reached 'max_users' limit", context do
    {:ok, state} = Experiment.init(context.exp)
    Enum.scan(0..4, state, fn _, state ->
      {:noreply, new_state} = Experiment.handle_cast({:inc_impression, "any_var_id"}, state)
      new_state
    end)
    assert_receive :end_experiment
    :timer.sleep(200)
  end
end
