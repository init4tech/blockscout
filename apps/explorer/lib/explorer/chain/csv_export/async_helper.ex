defmodule Explorer.Chain.CsvExport.AsyncHelper do
  @moduledoc """
  Async CSV export helper functions.
  """

  alias Explorer.HttpClient
  alias Tesla.Multipart

  def upload_file(file_path, filename, uuid) do
    file_size = File.stat!(file_path).size
    chunk_size = chunk_size()

    result =
      file_path
      |> File.stream!(chunk_size)
      |> Stream.with_index()
      |> Enum.reduce_while(:ok, fn {chunk, index}, _acc ->
        case upload_chunk(chunk, uuid, file_size, index * chunk_size) do
          :ok -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case result do
      :ok -> complete_upload(uuid, filename, file_size)
      error -> error
    end
  after
    File.rm(file_path)
  end

  defp upload_chunk(chunk, uuid, filesize, offset) do
    multipart =
      Multipart.new()
      |> Multipart.add_file_content(chunk, "chunk", name: "file")
      |> Multipart.add_field("uuid", uuid)
      |> Multipart.add_field("filesize", to_string(filesize))
      |> Multipart.add_field("offset", to_string(offset))

    case HttpClient.post(
           gokapi_chunk_upload_url(),
           multipart,
           headers: [api_key_header()]
         ) do
      {:ok, %{status_code: 200}} -> :ok
      error -> {:error, error}
    end
  end

  def complete_upload(uuid, filename, filesize, content_type \\ "application/csv", non_blocking? \\ true) do
    result =
      HttpClient.post(
        gokapi_chunk_complete_url(),
        nil,
        headers: [
          api_key_header(),
          {"uuid", uuid},
          {"filename", filename},
          {"filesize", to_string(filesize)},
          {"contenttype", content_type},
          {"allowedDownloads", to_string(gokapi_upload_allowed_downloads())},
          {"expiryDays", to_string(gokapi_upload_expiry_days())},
          {"nonblocking", to_string(non_blocking?)}
        ]
      )

    with {:ok, %{status_code: 200, body: body}} <- result,
         {:ok, %{"FileInfo" => %{"Id" => file_id}}} <- Jason.decode(body) do
      {:ok, file_id}
    else
      error -> {:error, error}
    end
  end

  def stream_to_temp_file(stream, uuid) do
    tmp_dir = tmp_dir()
    file_path = Path.join(tmp_dir, "csv_export_#{uuid}.csv")
    File.mkdir_p!(tmp_dir)

    File.open!(file_path, [:write, :binary], fn file ->
      stream
      |> Stream.each(fn chunk ->
        :file.write(file, chunk)
      end)
      |> Stream.run()
    end)

    {:ok, file_path}
  end

  defp csv_export_config do
    Application.get_env(:explorer, Explorer.Chain.CsvExport)
  end

  defp chunk_size do
    csv_export_config()[:chunk_size]
  end

  defp tmp_dir do
    csv_export_config()[:tmp_dir]
  end

  defp gokapi_url do
    csv_export_config()[:gokapi_url]
  end

  defp gokapi_api_key do
    csv_export_config()[:gokapi_api_key]
  end

  defp gokapi_upload_expiry_days do
    csv_export_config()[:gokapi_upload_expiry_days]
  end

  defp gokapi_upload_allowed_downloads do
    csv_export_config()[:gokapi_upload_allowed_downloads]
  end

  defp gokapi_chunk_upload_url do
    "#{gokapi_chunk_url()}/add"
  end

  defp gokapi_chunk_complete_url do
    "#{gokapi_chunk_url()}/complete"
  end

  defp gokapi_chunk_url do
    "#{gokapi_url()}/chunk"
  end

  defp api_key_header do
    {"apikey", gokapi_api_key()}
  end
end
