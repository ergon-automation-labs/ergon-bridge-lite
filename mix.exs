defmodule BotArmyBridgeLite.MixProject do
  use Mix.Project

  @version "0.1.7"

  def project do
    [
      app: :bot_army_bridge_lite,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      default_release: :bridge_lite_bot,
      releases: [
        # Release name must match the starter's compose convention <short>_bot
        # (service bridge_lite_bot runs `mix release ${BOT_NAME}`). Kept
        # :bridge_lite as an alias so existing invocations keep working.
        bridge_lite_bot: [
          applications: [
            bot_army_library_runtime: :permanent,
            bot_army_bridge_lite: :permanent
          ],
          validate_compile_env: false
        ],
        bridge_lite: [
          applications: [
            bot_army_library_runtime: :permanent,
            bot_army_bridge_lite: :permanent
          ],
          validate_compile_env: false
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BotArmyBridgeLite.Application, []}
    ]
  end

  defp deps do
    [
      {:bot_army_library_core, path: "../bot_army_library_core"},
      {:bot_army_library_runtime, path: "../bot_army_library_runtime", override: true},
      {:gnat, "~> 1.6"},
      {:jason, "~> 1.4"},
      {:elixir_uuid, "~> 1.2"},
      {:logger_json, "~> 5.1"},

      # Dev/Test
      {:ex_doc, "~> 0.30", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test]},
      {:excoveralls, "~> 0.17", only: :test},
      {:mox, "~> 1.0", only: :test}
    ]
  end
end
