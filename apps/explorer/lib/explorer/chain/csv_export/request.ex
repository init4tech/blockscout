defmodule Explorer.Chain.CsvExport.Request do
  @moduledoc """
  Represents an asynchronous CSV export request.

  When the requested export period exceeds `CSV_EXPORT_ASYNC_LOAD_THRESHOLD`,
  the export is processed asynchronously via an Oban job. This schema tracks
  the request lifecycle and provides a UUID for the user to poll for the result.
  """

  use Explorer.Schema

  alias Explorer.Chain.CsvExport.Worker
  alias Explorer.Repo

  @primary_key false
  typed_schema "csv_export_requests" do
    field(:id, Ecto.UUID, primary_key: true, autogenerate: true)
    field(:remote_ip_hash, :binary, null: false)
    field(:file_id, :string)

    timestamps()
  end

  @required_attrs ~w(remote_ip_hash)a
  @optional_attrs ~w(file_id)a

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = request, attrs \\ %{}) do
    request
    |> cast(attrs, @required_attrs ++ @optional_attrs)
    |> validate_required(@required_attrs)
  end

  @doc """
  Creates a new async CSV export request for the given remote IP address.

  The IP is hashed with SHA-256 before storage. Returns `{:ok, request}` on success,
  or `{:error, :too_many_pending_requests}` if the IP already has `max_pending_tasks`
  requests with `file_id` still `nil`.
  """
  @spec create(String.t()) :: {:ok, t()} | {:error, :too_many_pending_requests} | {:error, Ecto.Changeset.t()}
  def create(remote_ip, %{
        address_hash: address_hash,
        start_period: start_period,
        end_period: end_period,
        module: module
      }) do
    remote_ip_hash = hash_ip(remote_ip)
    max_pending = max_pending_tasks_per_ip()

    pending_count =
      __MODULE__
      |> where([r], r.remote_ip_hash == ^remote_ip_hash and is_nil(r.file_id))
      |> select([r], count(r.id))
      |> Repo.one()

    if pending_count >= max_pending do
      {:error, :too_many_pending_requests}
    else
      with {:ok, request} <-
             %__MODULE__{}
             |> changeset(%{remote_ip_hash: remote_ip_hash})
             |> Repo.insert(),
           {:ok, job} <-
             %{
               request_id: request.id,
               address_hash: address_hash,
               start_period: start_period,
               end_period: end_period,
               module: module
             }
             |> Worker.new()
             |> Oban.insert() do
        {:ok, %{request: request, job: job}}
      else
        {:error, error} -> {:error, error}
      end
    end
  end

  defp hash_ip(ip) do
    :crypto.hash(:sha256, ip)
  end

  defp max_pending_tasks_per_ip do
    Application.get_env(:explorer, Explorer.Chain.CsvExport)[:max_pending_tasks_per_ip]
  end
end
