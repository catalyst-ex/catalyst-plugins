defmodule Catalyst.Plugins.Waffle do
  use Catalyst.Plugin
  alias Catalyst.Execution

  @impl true
  def run(execution, opts \\ []) do
    otp = Execution.otp_app(execution)
    app_module = Execution.app_module(execution)
    provider = Keyword.get(opts, :provider, :gcs)
    uploads_module = Module.concat([app_module, "Uploads"])

    uploads_module_content =
      template_path(["waffle", "uploads.eex"])
      |> File.read!()
      |> EEx.eval_string(uploads_module: uploads_module)

    uploads_path = Path.join(["lib", "#{otp}", "uploads", "uploads.ex"])

    [
      # Add dependencies
      {Actions.AddDependency, name: :waffle, version: "1.1.9"},
      {Actions.AddDependency, name: :waffle_ecto, version: "0.0.12"},
      {Actions.AddFile, path: uploads_path, content: uploads_module_content},

      # Patch dev config to use local storage provider
      {Actions.PatchFile,
       path: Path.join("config", "dev.exs"),
       target: nil,
       content: """
       config :waffle,
        storage: Waffle.Storage.Local,
        storage_dir_prefix: "priv/static/uploads",
        asset_host: "http://localhost:4000/uploads"
       """,
       position: :end}
    ] ++ provider(provider, otp, app_module)
  end

  defp provider(:gcs, otp, app_module) do
    goth_fetcher_module = Module.concat([app_module, "Storage", "GothFetcher"])
    goth_process_module = Module.concat([app_module, "Goth"])

    goth_fetcher_module_content =
      template_path(["waffle", "goth_fetcher.eex"])
      |> File.read!()
      |> EEx.eval_string(
        goth_fetcher_module: goth_fetcher_module,
        goth_process_module: goth_process_module
      )

    application_path = Path.join(["lib", "#{otp}", "application.ex"])
    goth_fetcher_path = Path.join(["lib", "#{otp}", "storage", "goth_fetcher.ex"])

    [
      # Add dependencies
      {Actions.AddDependency, name: :waffle_gcs, version: "~> 0.2"},
      {Actions.AddDependency, name: :goth, version: "~> 1.4"},
      {Actions.MixTask, name: "deps.get"},

      # Add token fetcher module for GCS
      {Actions.AddFile, path: goth_fetcher_path, content: goth_fetcher_module_content},

      # Patch application.ex to register Goth process for prod only
      {Actions.PatchFile,
       path: application_path,
       target: :start,
       content: """
       children =
         if Mix.env() == :prod do
           children ++ [{Goth, name: #{inspect(goth_process_module)}}]
         else
           children
         end
       """,
       position: :after,
       anchor: fn
         {:=, _, [{:children, _, _}, _rhs]} -> true
         _ -> false
       end},

      # Patch prod config to use GCS provider
      {Actions.PatchFile,
       path: Path.join("config", "prod.exs"),
       target: nil,
       content: """
       config :waffle,
        storage: Waffle.Storage.Google.CloudStorage,
        token_fetcher: #{inspect(goth_fetcher_module)},
        version_timeout: 120_000
       """,
       position: :end},

      # Patch runtime config to use GCS provider for prod only
      {Actions.PatchFile,
       path: Path.join(["config", "runtime.exs"]),
       target: nil,
       content: """
       if config_env() == :prod do
           config :waffle,
             bucket: System.fetch_env!("GCS_BUCKET"),
             asset_host: System.fetch_env!("GCS_ASSET_HOST")

           config :goth,
             json: System.fetch_env!("GOOGLE_APPLICATION_CREDENTIALS_JSON")|> Jason.decode!()
       end
       """,
       position: :end}
    ]
  end

  defp provider(:aws, _otp, _app_module) do
    [
      # Add dependencies
      {Actions.AddDependency, name: :ex_aws, version: "~> 2.1.2"},
      {Actions.AddDependency, name: :ex_aws_s3, version: "~> 2.0"},
      {Actions.AddDependency, name: :sweet_xml, version: "~> 0.6"},
      {Actions.MixTask, name: "deps.get"},

      # Patch config to set codec for aws sdk
      {Actions.PatchFile,
       path: Path.join("config", "config.exs"),
       target: nil,
       content: """
       config :ex_aws,
        json_codec: Jason
       """,
       position: :end},

      # Patch prod config to use AWS S3 provider
      {Actions.PatchFile,
       path: Path.join("config", "prod.exs"),
       target: nil,
       content: """
       config :waffle,
        storage: Waffle.Storage.S3,
        version_timeout: 120_000
       """,
       position: :end},

      # Patch runtime config to use AWS sdk and S3 provider for prod only
      {Actions.PatchFile,
       path: Path.join(["config", "runtime.exs"]),
       target: nil,
       content: """
       if config_env() == :prod do
          config :ex_aws,
            access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
            secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY"),
            region: System.fetch_env!("AWS_REGION")


          config :waffle,
            bucket: System.fetch_env!("AWS_S3_BUCKET"),
            asset_host: System.fetch_env!("AWS_ASSET_HOST")
       end
       """,
       position: :end}
    ]
  end

  defp template_path(filename) when is_binary(filename) do
    template_path([filename])
  end

  defp template_path(path) when is_list(path) do
    Application.app_dir(
      :catalyst,
      Path.join(["priv", "templates"] ++ path)
    )
  end
end
