defmodule Xperiments.Experiment do
  @moduledoc """
  The module stores all information about an experiment.
  It belongs to parents: Users and Application. And has many_to_many
  for exclusion logic, so it's possible to set which experiments should
  be excluded from each other.

  *Variants* and *rules* are stored in JSONB fields.
  """
  use Xperiments.Web, :model
  alias Xperiments.{Application, User, Variant, Rule}

  use EctoStateMachine,
    states: [:draft, :running, :stopped, :terminated, :deleted],
    events: [
      [
        name:  :run,
        from:  [:draft, :stopped],
        to:    :running
      ], [
        name:  :stop,
        from:  [:running],
        to:    :stopped
      ], [
        name:  :terminate,
        from:  [:stopped],
        to:    :terminated
      ], [
        name:  :delete,
        from:  [:terminated, :draft],
        to:    :deleted
      ]
    ]

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "experiments" do
    field :name, :string
    field :description, :string
    field :start_date, :utc_datetime
    field :end_date, :utc_datetime
    field :sampling_rate, :decimal, default: 100
    field :max_users, :integer
    field :state, :string, default: "draft"

    belongs_to :application, Application

    many_to_many :exclusions, __MODULE__, join_through: "experiments_exclusions",
      join_keys: [experiment_a_id: :id, experiment_b_id: :id]

    embeds_many :variants, Variant
    embeds_many :rules, Rule

    timestamps()
  end

  @allowed_params ~w(name description start_date end_date sampling_rate max_users)

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, @allowed_params)
    |> validate_required([:name, :description, :start_date, :end_date, :sampling_rate])
    |> validate_end_date_greater_start_date([:start_date, :end_date])
    |> validate_current_or_future_date(:start_date)
    |> validate_current_or_future_date(:end_date)
    |> validate_number(:sampling_rate, greater_than: 0, less_than_or_equal_to: 100)
    |> maybe_validate_number(:max_users, greater_than: 0)
  end

  def changeset_with_embeds(struct, params \\ %{}) do
    struct
    |> changeset(params)
    |> cast_embed(:variants, required: true)
    |> cast_embed(:rules)
  end

  # TODO: Make a refactor for dates validation
  def validate_end_date_greater_start_date(changeset, [start_date_field, end_date_field]) do
    # TODO: use `with` here
    start_date = get_field(changeset, start_date_field)
    end_date = get_field(changeset, end_date_field)
    do_compare_two_dates(changeset, :__shared__, end_date, start_date, "End date must be greater than start date")
  end

  def validate_current_or_future_date(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      date -> do_compare_two_dates(changeset, field, date, DateTime.utc_now, "Date in the past")
    end
  end

  defp do_compare_two_dates(changeset, _, nil, nil, _), do: changeset
  defp do_compare_two_dates(changeset, field, start_date, end_date, message) do
    case DateTime.compare(start_date, end_date) do
      :lt -> add_error(changeset, field, message)
      _ -> changeset
    end
  end

  @doc """
  Validate a number if it set only, otherwise do nothing
  """
  def maybe_validate_number(changeset, nil, _opts), do: changeset
  def maybe_validate_number(changeset, field, opts) do
    validate_number(changeset, field, opts)
  end

  ## Serializer
  defimpl Poison.Encoder, for: __MODULE__ do
    def encode(model, opts) do
      model
      |> Map.from_struct
      |> Map.drop([:__meta__, :__struct__])
      |> Poison.encode!
    end
  end
end
