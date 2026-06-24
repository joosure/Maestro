defmodule SymphonyElixir.Agent.ExecutionPlan.Store.Command do
  @moduledoc false

  defmodule Create do
    @moduledoc false
    @enforce_keys [:plan]
    defstruct [:plan, opts: []]

    @type t :: %__MODULE__{plan: map(), opts: keyword()}
  end

  defmodule Fetch do
    @moduledoc false
    @enforce_keys [:plan_id]
    defstruct [:plan_id]

    @type t :: %__MODULE__{plan_id: String.t()}
  end

  defmodule Delete do
    @moduledoc false
    @enforce_keys [:plan_id]
    defstruct [:plan_id]

    @type t :: %__MODULE__{plan_id: String.t()}
  end

  defmodule Replace do
    @moduledoc false
    @enforce_keys [:plan_id, :replacement, :expected_revision]
    defstruct [:plan_id, :replacement, :expected_revision, opts: []]

    @type t :: %__MODULE__{
            plan_id: String.t(),
            replacement: map(),
            expected_revision: pos_integer(),
            opts: keyword()
          }
  end

  defmodule UpdatePlanStatus do
    @moduledoc false
    @enforce_keys [:plan_id, :next_status, :expected_revision]
    defstruct [:plan_id, :next_status, :expected_revision, opts: []]

    @type t :: %__MODULE__{
            plan_id: String.t(),
            next_status: String.t(),
            expected_revision: pos_integer(),
            opts: keyword()
          }
  end

  defmodule UpdateItemStatus do
    @moduledoc false
    @enforce_keys [:plan_id, :item_id, :next_status, :expected_revision]
    defstruct [:plan_id, :item_id, :next_status, :expected_revision, opts: []]

    @type t :: %__MODULE__{
            plan_id: String.t(),
            item_id: String.t(),
            next_status: String.t(),
            expected_revision: pos_integer(),
            opts: keyword()
          }
  end

  defmodule AppendEvidenceRef do
    @moduledoc false
    @enforce_keys [:plan_id, :item_id, :evidence_ref, :expected_revision]
    defstruct [:plan_id, :item_id, :evidence_ref, :expected_revision, opts: []]

    @type t :: %__MODULE__{
            plan_id: String.t(),
            item_id: String.t(),
            evidence_ref: map(),
            expected_revision: pos_integer(),
            opts: keyword()
          }
  end

  defmodule UpsertAgentItems do
    @moduledoc false
    @enforce_keys [:plan_id, :items, :expected_revision]
    defstruct [:plan_id, :items, :expected_revision, opts: []]

    @type t :: %__MODULE__{
            plan_id: String.t(),
            items: [map()],
            expected_revision: pos_integer(),
            opts: keyword()
          }
  end

  defmodule Reset do
    @moduledoc false
    defstruct []

    @type t :: %__MODULE__{}
  end

  @type t ::
          Create.t()
          | Fetch.t()
          | Delete.t()
          | Replace.t()
          | UpdatePlanStatus.t()
          | UpdateItemStatus.t()
          | AppendEvidenceRef.t()
          | UpsertAgentItems.t()
          | Reset.t()
end
