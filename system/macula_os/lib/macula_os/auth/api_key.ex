defmodule MaculaOs.Auth.ApiKey do
  @moduledoc """
  API Key authentication and authorization for MaculaOs proxy.

  Validates API keys and maps them to namespaces for topic prefix enforcement.

  Current implementation: Simple validation against configured keys
  Future: Integration with application registration service
  """
  require Logger

  @doc """
  Validates an API key and returns the associated namespace.

  Returns:
  - `{:ok, namespace, metadata}` if valid
  - `{:error, reason}` if invalid

  ## Examples

      iex> validate("myorg-webapp-550e8400")
      {:ok, "myorg.webapp", %{org: "myorg", app: "webapp"}}

      iex> validate("invalid-key")
      {:error, :invalid_api_key}
  """
  def validate(api_key) when is_binary(api_key) do
    # Current implementation: lookup from environment/config
    # Future: HTTP call to registration service
    case lookup_key(api_key) do
      {:ok, namespace, metadata} ->
        Logger.info("API key validated for namespace: #{namespace}")
        {:ok, namespace, metadata}

      :error ->
        Logger.warning("Invalid API key: #{String.slice(api_key, 0..7)}...")
        {:error, :invalid_api_key}
    end
  end

  def validate(_), do: {:error, :invalid_api_key}

  @doc """
  Checks if a topic is allowed for the given namespace.

  Topics must be prefixed with the namespace.

  ## Examples

      iex> allowed_topic?("myorg.webapp", "myorg.webapp.user.created")
      true

      iex> allowed_topic?("myorg.webapp", "otherapp.service.event")
      false
  """
  def allowed_topic?(namespace, topic) when is_binary(namespace) and is_binary(topic) do
    String.starts_with?(topic, namespace)
  end

  def allowed_topic?(_, _), do: false

  ## Private Functions

  defp lookup_key(api_key) do
    # Check environment variable for configured keys
    # Format: MACULA_API_KEYS="key1:namespace1:org1:app1,key2:namespace2:org2:app2"
    configured_keys = System.get_env("MACULA_API_KEYS", "")

    if configured_keys != "" do
      lookup_from_env(api_key, configured_keys)
    else
      # Development mode: accept any key with format "namespace-app-uuid"
      # and derive namespace from key structure
      lookup_dev_mode(api_key)
    end
  end

  defp lookup_from_env(api_key, configured_keys) do
    configured_keys
    |> String.split(",", trim: true)
    |> Enum.find_value(:error, fn entry ->
      case String.split(entry, ":", parts: 4) do
        [^api_key, namespace, org, app] ->
          {:ok, namespace, %{org: org, app: app}}

        _ ->
          nil
      end
    end)
  end

  defp lookup_dev_mode(api_key) do
    # Development: parse key format "org-app-uuid" → namespace "org.app"
    case String.split(api_key, "-", parts: 3) do
      [org, app, _uuid] when org != "" and app != "" ->
        namespace = "#{org}.#{app}"
        {:ok, namespace, %{org: org, app: app}}

      _ ->
        :error
    end
  end
end
