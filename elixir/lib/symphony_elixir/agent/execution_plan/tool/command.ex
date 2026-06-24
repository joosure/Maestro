defmodule SymphonyElixir.Agent.ExecutionPlan.Tool.Command do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Payload

  defmodule Snapshot do
    @moduledoc false
    @enforce_keys [:plan_id]
    defstruct [:plan_id]

    @type t :: %__MODULE__{plan_id: String.t()}
  end

  defmodule Create do
    @moduledoc false
    @enforce_keys [:plan]
    defstruct [:plan]

    @type t :: %__MODULE__{plan: Payload.Plan.t()}
  end

  defmodule MergeItems do
    @moduledoc false
    @enforce_keys [:plan_id, :plan_revision, :items]
    defstruct [:plan_id, :plan_revision, :items]

    @type t :: %__MODULE__{
            plan_id: String.t(),
            plan_revision: pos_integer(),
            items: Payload.ItemSet.t()
          }
  end

  defmodule UpdateItem do
    @moduledoc false
    @enforce_keys [:plan_id, :item_id, :status, :plan_revision]
    defstruct [:plan_id, :item_id, :status, :plan_revision]

    @type t :: %__MODULE__{
            plan_id: String.t(),
            item_id: String.t(),
            status: String.t(),
            plan_revision: pos_integer()
          }
  end

  defmodule AppendEvidenceRef do
    @moduledoc false
    @enforce_keys [:plan_id, :item_id, :evidence_ref, :plan_revision]
    defstruct [:plan_id, :item_id, :evidence_ref, :plan_revision]

    @type t :: %__MODULE__{
            plan_id: String.t(),
            item_id: String.t(),
            evidence_ref: Payload.EvidenceRef.t(),
            plan_revision: pos_integer()
          }
  end

  @type t ::
          Snapshot.t()
          | Create.t()
          | MergeItems.t()
          | UpdateItem.t()
          | AppendEvidenceRef.t()
end
