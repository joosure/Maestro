defmodule SymphonyElixir.RepoProvider.CNB.Normalizer.Discussion do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.CNB.Normalizer.Values
  alias SymphonyElixir.RepoProvider.Error

  @spec normalize_issue_comment(map()) :: map()
  def normalize_issue_comment(comment) when is_map(comment) do
    %{
      "id" => Values.opaque_id(Values.field_value(comment, "id", :id)),
      "body" => Values.field_value(comment, "body", :body) || "",
      "created_at" => Values.field_value(comment, "created_at", :created_at),
      "updated_at" => Values.field_value(comment, "updated_at", :updated_at),
      "user" => normalize_user(Values.field_value(comment, "author", :author) || %{})
    }
  end

  @spec normalize_review(map()) :: map()
  def normalize_review(review) when is_map(review) do
    %{
      "id" => Values.opaque_id(Values.field_value(review, "id", :id)),
      "body" => Values.field_value(review, "body", :body) || "",
      "created_at" => Values.field_value(review, "created_at", :created_at),
      "submitted_at" =>
        Values.field_value(review, "updated_at", :updated_at) ||
          Values.field_value(review, "created_at", :created_at),
      "state" => review |> Values.field_value("state", :state) |> to_string() |> String.upcase(),
      "user" => normalize_user(Values.field_value(review, "author", :author) || %{})
    }
  end

  @spec normalize_review_comment(map()) :: map()
  def normalize_review_comment(comment) when is_map(comment) do
    %{
      "id" => Values.opaque_id(Values.field_value(comment, "id", :id)),
      "body" => Values.field_value(comment, "body", :body) || "",
      "created_at" => Values.field_value(comment, "created_at", :created_at),
      "updated_at" => Values.field_value(comment, "updated_at", :updated_at),
      "path" => Values.field_value(comment, "path", :path),
      "commit_id" => Values.field_value(comment, "commit_hash", :commit_hash),
      "in_reply_to_id" => Values.reply_id(Values.field_value(comment, "reply_to_comment_id", :reply_to_comment_id)),
      "pull_request_review_id" => Values.opaque_id(Values.field_value(comment, "review_id", :review_id)),
      "user" => normalize_user(Values.field_value(comment, "author", :author) || %{})
    }
  end

  @spec normalize_user(map() | term()) :: map()
  def normalize_user(user) when is_map(user) do
    username =
      Values.field_value(user, "username", :username) || Values.field_value(user, "login", :login) || ""

    %{
      "login" => username,
      "type" => if(Values.field_value(user, "is_npc", :is_npc), do: "Bot", else: "User")
    }
  end

  def normalize_user(_user), do: %{"login" => "", "type" => "User"}

  @spec review_id_values(map()) :: list()
  def review_id_values(review) do
    case Values.field_value(review, "id", :id) do
      nil -> []
      "" -> []
      id -> [id]
    end
  end

  @spec review_comment_review_id(map(), String.t()) :: {:ok, term()} | {:error, Error.t()}
  def review_comment_review_id(comment, reply_to) do
    case Values.field_value(comment, "review_id", :review_id) do
      nil ->
        {:error,
         Error.runtime_failure(
           :cnb_review_id_not_found,
           "Unable to resolve CNB review_id for comment #{reply_to}"
         )}

      "" ->
        {:error,
         Error.runtime_failure(
           :cnb_review_id_not_found,
           "Unable to resolve CNB review_id for comment #{reply_to}"
         )}

      review_id ->
        {:ok, review_id}
    end
  end
end
