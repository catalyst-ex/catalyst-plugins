defmodule Catalyst.Plugins.Graphql do
  use Catalyst.Plugin
  alias Sourceror.Zipper
  alias Catalyst.Execution

  @impl true
  def run(execution, _opts \\ []) do
    otp = Execution.otp_app(execution)
    app_module = Execution.app_module(execution)
    endpoint_path = Path.join(["lib", "#{otp}_web", "endpoint.ex"])
    router_path = Path.join(["lib", "#{otp}_web", "router.ex"])
    schema_path = Path.join(["lib", to_string(otp), "schema.ex"])
    schema_module = Module.concat([app_module, "Schema"])

    [
      # Dependency
      {Actions.AddDependency, name: :absinthe, version: "~> 1.7"},
      {Actions.AddDependency, name: :absinthe_plug, version: "~> 1.5"},
      {Actions.AddDependency, name: :absinthe_upload_standard, version: "~> 0.1.0"},
      {Actions.PatchFile,
       path: endpoint_path,
       target: fn root_zipper ->
         root_zipper
         |> Zipper.find(fn
           {:plug, _, [{:__aliases__, _, [:Plug, :Parsers]} | _]} -> true
           _ -> false
         end)
         |> case do
           nil ->
             nil

           plug_zipper ->
             plug_zipper
             |> Zipper.find(fn
               {k, v} ->
                 key_match? =
                   case k do
                     {:__block__, _, [:parsers]} -> true
                     _ -> false
                   end

                 value_is_list? =
                   case v do
                     {:__block__, _, [list]} when is_list(list) -> true
                     _ -> false
                   end

                 key_match? and value_is_list?

               _ ->
                 false
             end)
             |> case do
               nil -> nil
               pair_zipper -> pair_zipper |> Zipper.down() |> Zipper.right()
             end
         end
       end,
       content: "Absinthe.Plug.Parser",
       position: :end},
      {Actions.PatchFile,
       path: endpoint_path,
       target: :defmodule,
       content: "plug AbsintheUploadStandard",
       position: :after,
       anchor: fn
         {:plug, _, [{:__aliases__, _, [:Plug, :Parsers]} | _]} -> true
         _ -> false
       end},
      {Actions.PatchFile,
       path: router_path,
       target: :defmodule,
       content: """
       scope "/graphql" do
         pipe_through :api

         forward "/", Absinthe.Plug, schema: #{inspect(schema_module)}
       end
       """,
       position: :end},
      {Actions.PatchFile,
       path: router_path,
       target: :defmodule,
       content: """
       scope "/graphiql" do
         pipe_through :api

         forward "/", Absinthe.Plug.GraphiQL,
           schema: #{inspect(schema_module)},
           interface: :simple
       end
       """,
       position: :end},
      {Actions.AddFile,
       path: schema_path,
       content: """
       defmodule #{inspect(schema_module)} do
         use Absinthe.Schema

         import_types(Absinthe.Type.Custom)
         import_types(Absinthe.Plug.Types)

         query do
            field :health, :string do
            resolve(fn _, _ -> {:ok, "ok"} end)
            end
         end
       end
       """},

      # Fetch deps
      {Actions.MixTask, name: "deps.get"}
    ]
  end
end
