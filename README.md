# PEATIO Client for Elixir

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add peatio_client to your list of dependencies in `mix.exs`:

        def deps do
          [{:peatio_client, "~> 0.1.0"}]
        end

  2. Ensure peatio_client is started before your application:

        def application do
          [applications: [:peatio_client]]
        end
