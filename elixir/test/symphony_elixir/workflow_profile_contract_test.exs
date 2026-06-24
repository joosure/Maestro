defmodule SymphonyElixir.WorkflowProfileContractTest.CodingPrDelivery do
  use ExUnit.Case, async: true

  use SymphonyElixir.WorkflowProfileContract,
    profile: SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile
end

defmodule SymphonyElixir.WorkflowProfileContractTest.RequirementAnalysis do
  use ExUnit.Case, async: true

  use SymphonyElixir.WorkflowProfileContract,
    profile: SymphonyElixir.Workflow.Profiles.RequirementAnalysis
end

defmodule SymphonyElixir.WorkflowProfileContractTest.RequirementRefinement do
  use ExUnit.Case, async: true

  use SymphonyElixir.WorkflowProfileContract,
    profile: SymphonyElixir.Workflow.Profiles.RequirementRefinement
end

defmodule SymphonyElixir.WorkflowProfileContractTest.ReviewRouting do
  use ExUnit.Case, async: true

  use SymphonyElixir.WorkflowProfileContract,
    profile: SymphonyElixir.Workflow.Profiles.ReviewRouting
end

defmodule SymphonyElixir.WorkflowProfileContractTest.Triage do
  use ExUnit.Case, async: true

  use SymphonyElixir.WorkflowProfileContract,
    profile: SymphonyElixir.Workflow.Profiles.Triage
end
