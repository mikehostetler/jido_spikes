defmodule Jarvis.Chat.ReviewNotice do
  @moduledoc "Incident recommendations delivered to the conversation that started a review."
  use Ecto.Schema
  import Ecto.Query
  alias Jarvis.Repo

  schema "review_notices" do
    field(:topic, :string)
    field(:review_id, :string)
    field(:action, :string)
    field(:text, :string)
  end

  def list(topic), do: Repo.all(from(n in __MODULE__, where: n.topic == ^topic, order_by: n.id))

  def record(
        %{chat_topic: "jarvis:chat:" <> _ = topic, review_id: id},
        %{status: "completed", recommendation: action} = review
      )
      when action in ["ROLLBACK", "INVESTIGATE", "MONITOR"] do
    previous =
      Repo.one(
        from(n in __MODULE__,
          where: n.review_id == ^id,
          order_by: [desc: n.id],
          limit: 1,
          select: n.action
        )
      )

    if previous != action do
      transition = if previous, do: "#{previous} → #{action}", else: action
      text = "#{transition}: #{review.answer}\nMemory IDs: #{Enum.join(review.memory_ids, ", ")}"
      Repo.insert!(%__MODULE__{topic: topic, review_id: id, action: action, text: text})
      Phoenix.PubSub.broadcast(Jarvis.PubSub, topic, :review_notice)
    end

    :ok
  end

  def record(_, _), do: :ok
end
