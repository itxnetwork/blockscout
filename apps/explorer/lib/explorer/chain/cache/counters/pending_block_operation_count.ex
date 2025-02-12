defmodule Explorer.Chain.Cache.Counters.PendingBlockOperationCount do
  @moduledoc """
  Cache for estimated `pending_block_operations` count.
  """

  use Explorer.Chain.MapCache,
    name: :pending_block_operations_count,
    key: :count,
    key: :async_task,
    global_ttl: Application.get_env(:explorer, __MODULE__)[:global_ttl],
    ttl_check_interval: :timer.seconds(1),
    callback: &async_task_on_deletion(&1)

  require Logger

  alias Explorer.Chain.Cache.Counters.LastFetchedCounter
  alias Explorer.Chain.Cache.Helper
  alias Explorer.Chain.PendingBlockOperation
  alias Explorer.Repo

  @cache_key "pending_block_operations_count"

  @doc """
  Estimated count of `t:Explorer.Chain.PendingBlockOperation.t/0`.

  """
  @spec estimated_count() :: non_neg_integer()
  def estimated_count do
    cached_value_from_ets = __MODULE__.get_count()

    if is_nil(cached_value_from_ets) do
      cached_value_from_db =
        @cache_key
        |> LastFetchedCounter.get()
        |> Decimal.to_integer()

      if cached_value_from_db === 0 do
        estimated_pending_block_operations_count()
      else
        cached_value_from_db
      end
    else
      cached_value_from_ets
    end
  end

  defp estimated_pending_block_operations_count do
    count = Helper.estimated_count_from("pending_block_operations")

    if is_nil(count), do: 0, else: max(count, 0)
  end

  defp handle_fallback(:count) do
    # This will get the task PID if one exists, check if it's running and launch
    # a new task if task doesn't exist or it's not running.
    # See next `handle_fallback` definition
    safe_get_async_task()

    {:return, nil}
  end

  defp handle_fallback(:async_task) do
    # If this gets called it means an async task was requested, but none exists
    # so a new one needs to be launched
    {:ok, task} =
      Task.start_link(fn ->
        try do
          result = Repo.aggregate(PendingBlockOperation, :count, timeout: :infinity)

          params = %{
            counter_type: @cache_key,
            value: result
          }

          LastFetchedCounter.upsert(params)

          set_count(%ConCache.Item{ttl: Helper.ttl(__MODULE__, "CACHE_PBO_COUNT_PERIOD"), value: result})
        rescue
          e ->
            Logger.debug([
              "Couldn't update pending_block_operations count: ",
              Exception.format(:error, e, __STACKTRACE__)
            ])
        end

        set_async_task(nil)
      end)

    {:update, task}
  end

  # By setting this as a `callback` an async task will be started each time the
  # `count` expires (unless there is one already running)
  defp async_task_on_deletion({:delete, _, :count}), do: safe_get_async_task()

  defp async_task_on_deletion(_data), do: nil
end
