defmodule Passme.Chat.Script.Base do
  @moduledoc false

  defmacro __using__(ops) do
    import Logger

    alias Passme.Chat.Interface, as: ChatInterface
    alias Passme.Chat.Script.Step
    alias Passme.Bot

    wait_time = :timer.seconds(30)

    script_input_timeout = :script_input_timeout

    steps =
      case Keyword.fetch(ops, :steps) do
        {:ok, l} when is_list(l) -> l
        _ -> []
      end

    quote do
      @behaviour Passme.Chat.Script.Handler

      defstruct module: __MODULE__,
                step: nil,
                timer: nil,
                parent_chat: nil,
                parent_user: nil,
                data: nil

      def new(user, chat, data \\ %{}) do
        %__MODULE__{
          step: first_step(),
          timer: Process.send_after(self(), unquote(script_input_timeout), unquote(wait_time)),
          parent_chat: chat,
          parent_user: user,
          data: data
        }
      end

      def set_step_result(%{step: {_, step}} = script, value) do
        case validate_value(step, value) do
          :ok ->
            {
              :ok,
              script
              |> Map.put(:timer, reset_input_timer(script.timer))
              |> Map.put(:data, Map.put(script.data, get_field_key(script), escape(value)))
            }

          {:error, msg} ->
            {:error, msg}
        end
      end

      def start_step(%__MODULE__{step: :end} = script), do: {:end, finish(script)}
      def start_step(%__MODULE__{step: {:end, _}} = script), do: {:end, finish(script)}
      def start_step(%__MODULE__{step: {_, %{processing: true}}} = script), do: {:error, script}

      def start_step(%__MODULE__{step: {key, step}} = script) do
        # If user tried to start script from group-chat, bot doesn't added to user private chat
        # telegram returns error
        case step_message(script) do
          {:ok, _} ->
            {
              :ok,
              script
              |> Map.put(:timer, reset_input_timer(script.timer))
              |> Map.put(:step, {key, Map.put(step, :processing, true)})
            }

          {:not_in_conversation, _} = tup ->
            info("Target user not added this bot to private chat to start script")
            Bot.private_chat_requested(tup, script.parent_chat.id, script.parent_user)
            {:ok, script}
        end
      end

      defp step_message(%__MODULE__{step: {_, step}} = script) do
        can_be_empty = get_step_key_value(step, :can_be_empty, get_field_key(script))
        Bot.msg(script.parent_user, ChatInterface.script_step(script, can_be_empty))
      end

      def next_step(%{step: step} = script) do
        Map.put(script, :step, get_next_step(step))
      end

      def abort_wr(%{timer: timer} = script) do
        cancel_timer(timer)
        abort(script)
      end

      defp validate_value(%Step{validate: nil}, _), do: :ok

      defp validate_value(%Step{validate: fun}, value) when is_function(fun),
        do: apply(fun, [value])

      defp validate_value(%Step{validate: fun}, _),
        do: raise("#{Step} key validate must be function")

      @spec get_next_step({atom(), Step.t()}) :: {atom(), Step.t()}
      defp get_next_step({_key, step}) do
        Enum.find(unquote(steps), :end, fn {x, _} ->
          x == step.next
        end)
      end

      defp finish(%{timer: timer} = script) do
        cancel_timer(timer)
        script
      end

      defp first_step, do: List.first(unquote(steps))

      defp cancel_timer(timer), do: Process.cancel_timer(timer, async: true, info: false)

      defp reset_input_timer(timer) do
        cancel_timer(timer)
        Process.send_after(self(), unquote(script_input_timeout), unquote(wait_time))
      end

      defp get_field_key(%__MODULE__{step: {key, data}}) do
        if Map.has_key?(data, :field) do
          data.field
        else
          key
        end
      end

      defoverridable get_field_key: 1

      @spec get_step_key_value(Step.t(), atom()) :: any()
      defp get_step_key_value(step, field) do
        Map.get(step, field)
      end

      @spec get_step_key_value(Step.t(), atom(), any()) :: any()
      defp get_step_key_value(step, field, arg) do
        field_value = Map.get(step, field)

        if is_function(field_value) do
          field_value.(arg)
        else
          field_value
        end
      end

      defp escape(nil), do: nil

      defp escape(value) do
        value
        |> String.replace(~r/(\*|\\|\_|\-)/, "\\\\" <> "\\1")
      end
    end
  end
end
