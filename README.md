# SiteEncrypt

![Build Status](https://github.com/sasa1977/site_encrypt/workflows/site_encrypt/badge.svg)

This project aims to provide integrated certification via [Let's encrypt](https://letsencrypt.org/) for sites implemented in Elixir.

Integrated certification means that you don't need to run any other OS process in background. Start your site for the first time, and it will obtain the certificate, and restart the endpoint. The system will also periodically renew the certificate, and when the new certificate is obtained, the endpoint will again be restarted.

The target projects are small-to-medium Elixir based sites which don't sit behind reverse proxies such as nginx.

In addition, the library ships with a basic ACME v2 server to facilitate local development without needing to start a bunch of docker images.

## Status

- The library is tested in a [simple production](https://www.theerlangelist.com), where it has been constantly running since mid 2018.
- The API is not stable. Expect breaking changes in the future.
- The documentation is non-existant.
- The tests are basic.

Use at your own peril :-)

## Dependencies

- [Certbot](https://certbot.eff.org/) >= 0.31 (ACME client used to obtain certificate)

## Using with Phoenix

### Local development

A basic demo Phoenix project is available [here](./demos/phoenix).

First, you need to add the dependency to `mix.exs`:

```elixir
defmodule PhoenixDemo.Mixfile do
  # ...

  defp deps do
    [
      # ...
      {:site_encrypt, github: "sasa1977/site_encrypt"}
    ]
  end
end
```

Don't forget to invoke `mix.deps` after that.

Next, extend your endpoint to implement `SiteEncrypt` behaviour:

```elixir
defmodule PhoenixDemo.Endpoint do
  # ...

  @behaviour SiteEncrypt

  # ...

  @impl SiteEncrypt
  def certification do
    [
      base_folder: Application.app_dir(:phoenix_demo, "priv") |> Path.join("certbot"),
      cert_folder: Application.app_dir(:phoenix_demo, "priv") |> Path.join("cert"),
      ca_url: {:local_acme_server, port: 4002},
      domain: "localhost",
      email: "admin@foo.bar"
      mode: unquote(if Mix.env() == :test, do: :manual, else: :auto)
    ]
  end

  @impl SiteEncrypt
  def handle_new_cert do
    # Invoked after certificate has been obtained.
    :ok
  end

  # ...
end
```

Include `plug SiteEncrypt.AcmeChallenge, __MODULE__` in your endpoint. If you have `plug Plug.SSL` specified, it has to be provided after `SiteEncrypt.AcmeChallenge`.

Configure https:

```elixir
defmodule PhoenixDemo.Endpoint do
  # ...

  @impl Phoenix.Endpoint
  def init(_key, config) do
    {:ok, Keyword.merge(config, https: [port: 4001] ++ SiteEncrypt.https_keys(__MODULE__))}
  end

  # ...
end
```

Finally, you need to start the endpoint via `SiteEncrypt`:

```elixir
defmodule PhoenixDemo.Application do
  use Application

  def start(_type, _args) do
    children = [{SiteEncrypt.Phoenix, PhoenixDemo.Endpoint}]
    opts = [strategy: :one_for_one, name: PhoenixDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # ...
end
```

And that's it! At this point you can start the system:

```
$ iex -S mix phx.server

22:10:13.938 [info]  Generating a temporary self-signed certificate. This certificate will be used until a proper certificate is issued by the CA server.
22:10:14.321 [info]  Running local ACME server at port 4002
22:10:14.356 [info]  Running PhoenixDemo.Endpoint with cowboy 2.7.0 at 0.0.0.0:4000 (http)
22:10:14.380 [info]  Running PhoenixDemo.Endpoint with cowboy 2.7.0 at 0.0.0.0:4001 (https)

# wait for about 10 seconds

# ...
22:10:20.568 [info]  Obtained new certificate for localhost
```

And visit your certified site at https://localhost:4001

The certificate issued by the integrated ACME server expires after 1000 years. Therefore, if you restart the site, the certificate won't be renewed.

If something goes wrong, usually if you abruptly took down the system in the middle of the certification, the certbot might not work again. In this case, you can just delete the contents of the certbot folder.

Of course, in real production you want to backup this folder after every change, and restore it if something is corrupt.

#### Testing

It's possible to add an automated test of the certification:

```elixir
defmodule PhoenixDemo.EndpointTest do
  use ExUnit.Case, async: false

  test "certification" do
    # This will verify the first certification, as well as renewals.
    SiteEncrypt.Phoenix.Test.verify_certification(PhoenixDemo.Endpoint, [
      ~U[2020-01-01 00:00:00Z],
      ~U[2020-02-01 00:00:00Z]
    ])
  end
end

```

### Production

To make it work in production, you need to own the domain and run your site there.

You need to change some parameters in `certification/1` callback.

```elixir
def certification() do
  [
    ca_url: "https://acme-v02.api.letsencrypt.org/directory",
    domain: "<DOMAIN NAME>",
    email: "<ADMIN EMAIL>"
    # other parameters can remain the same
  ]
end
```

For staging, you can use https://acme-staging-v02.api.letsencrypt.org/directory. Make sure to change the domain name as well.

In both cases (staging and production certification), the site must be publicly reachable at `http://<DOMAIN NAME>`.

It's up to you to decide how to vary the settings between local development and production.

## Backup and restore

SiteEncrypt supports automatic backup. To enable it, include `backup: path_to_backup_tgz` in the options returned by `config/0`. Every time a new certificate is obtained, the entire content of the `base_folder` will be backed up to this file as a compressed tarball. This happens before `handle_new_cert` is invoked.

Note that this file is not encrypted, so make sure to restrict the access to it, or otherwise postprocess it (e.g. encrypt it) in the `handle_new_cert` callback.

The backup is automatically restored when the endpoint is started if the following conditions are met:

1. The backup file exists at the location configured via the `:backup` option
2. The `base_folder` doesn't exist

Note that a successful restore is treated as a certificate renewal, which means that the new certificate will be backed up (if configured), and `handle_new_cert` will be invoked.

## Force renewal

To force renew a certificate, you can invoke `SiteEncrypt.Certifier.force_renew(YourEndpointModule)`. This will temporarily pause the periodic renewal (waiting for it to finish if it happens to be running), renew the certificate, and resume the periodic renewal. The new certificate will be backed up, and `handle_new_cert` will be invoked.

## License

[MIT](./LICENSE)
