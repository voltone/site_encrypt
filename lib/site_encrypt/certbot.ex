defmodule SiteEncrypt.Certbot do
  @type https_keys :: [keyfile: String.t(), certfile: String.t(), cacertfile: String.t()]
  @type ensure_cert :: {:new_cert, String.t()} | {:no_change, String.t()} | {:error, String.t()}

  @spec keys_available?(SiteEncrypt.config()) :: boolean
  def keys_available?(config),
    do: Enum.all?([keyfile(config), certfile(config), cacertfile(config)], &File.exists?/1)

  @spec https_keys(SiteEncrypt.config()) :: {:ok, https_keys} | :error
  def https_keys(config) do
    if keys_available?(config) do
      {:ok,
       [
         keyfile: keyfile(config),
         certfile: certfile(config),
         cacertfile: cacertfile(config)
       ]}
    else
      :error
    end
  end

  @spec ensure_cert(SiteEncrypt.config(), force_renewal: boolean) :: ensure_cert()
  def ensure_cert(config, opts \\ []) do
    ensure_folders(config)
    original_keys_sha = keys_sha(config)
    result = if keys_available?(config), do: renew(config, opts), else: certonly(config)

    case result do
      {output, 0} ->
        if keys_sha(config) != original_keys_sha,
          do: {:new_cert, output},
          else: {:no_change, output}

      {output, _error} ->
        {:error, output}
    end
  end

  @spec challenge_file(String.t(), String.t()) :: String.t()
  def challenge_file(base_folder, challenge) do
    Path.join([
      webroot_folder(%{base_folder: base_folder}),
      ".well-known",
      "acme-challenge",
      challenge
    ])
  end

  defp ensure_folders(config) do
    Enum.each(
      [config_folder(config), work_folder(config), webroot_folder(config)],
      &File.mkdir_p!/1
    )
  end

  defp certonly(config) do
    certbot_cmd(
      config,
      ~w(certonly -m #{config.email} --webroot --webroot-path #{webroot_folder(config)} --agree-tos) ++
        domain_params(config)
    )
  end

  defp renew(config, opts) do
    args =
      Enum.reduce(
        opts,
        ~w(-m #{config.email} --agree-tos --no-random-sleep-on-renew --cert-name #{config.domain}),
        &add_arg/2
      )

    certbot_cmd(config, ["renew" | args])
  end

  defp add_arg({:force_renewal, false}, args), do: args
  defp add_arg({:force_renewal, true}, args), do: ["--force-renewal" | args]

  defp certbot_cmd(config, args),
    do: System.cmd("certbot", args ++ common_args(config), stderr_to_stdout: true)

  defp common_args(config) do
    ~w(
      --server #{ca_url(config.ca_url)}
      --work-dir #{work_folder(config)}
      --config-dir #{config_folder(config)}
      --logs-dir #{log_folder(config)}
      --no-self-upgrade
      --non-interactive
    )
  end

  defp ca_url({:local_acme_server, opts}),
    do: "http://localhost:#{Keyword.fetch!(opts, :port)}/directory"

  defp ca_url(ca_url), do: ca_url

  defp domain_params(config), do: Enum.map([config.domain | config.extra_domains], &"-d #{&1}")

  defp keys_folder(config), do: Path.join(~w(#{config_folder(config)} live #{config.domain}))
  defp config_folder(config), do: Path.join(config.base_folder, "config")
  defp log_folder(config), do: Path.join(config.base_folder, "log")
  defp work_folder(config), do: Path.join(config.base_folder, "work")
  defp webroot_folder(config), do: Path.join(config.base_folder, "webroot")

  defp keyfile(config), do: Path.join(keys_folder(config), "privkey.pem")
  defp certfile(config), do: Path.join(keys_folder(config), "cert.pem")
  defp cacertfile(config), do: Path.join(keys_folder(config), "chain.pem")

  defp keys_sha(config) do
    case https_keys(config) do
      :error ->
        nil

      {:ok, keys} ->
        :crypto.hash(
          :md5,
          keys |> Keyword.values() |> Stream.map(&File.read!/1) |> Enum.join()
        )
    end
  end
end
