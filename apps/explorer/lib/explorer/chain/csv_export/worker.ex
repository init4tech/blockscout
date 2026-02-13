defmodule Explorer.Chain.CsvExport.Worker do
  use Oban.Worker, queue: :csv_export

  @impl Oban.Worker
  def perform(
        %Job{
          args: %{
            request_id: request_id,
            address_hash: address_hash,
            start_period: start_period,
            end_period: end_period,
            module: module
          }
        } = job
      ) do
    csv_export_module = String.to_atom(module)
    filename = "#{address_hash}_#{start_period}_#{end_period}.csv"

    csv_export_module.export(address_hash, start_period, end_period)
    |> AsyncHelper.upload_file(filename, request_id)
  end
end
