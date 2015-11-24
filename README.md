# PEATIO Client for Elixir

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add peatio_client to your list of dependencies in `mix.exs`:

        def deps do
          [{:peatio_client, "~> 0.1.1"}]
        end

  2. Ensure peatio_client is started before your application:

        def application do
          [applications: [:peatio_client]]
        end

## Usage

More API document please visit [PEATIO API](https://app.peatio.com/documents/api_v2)

```
# Public API
PeatioClient.ticker market
PeatioClient.trades market

# Private API
# Create a API server with your key and secret.
PeatioClient.Server.start_link id, key, secret

# Get Member info
PeatioClient.me id

# Entry Order
PeatioClient.ask id, market, [{private, volume}, ...]
PeatioClient.bid id, market, [{private, volume}, ...]
PeatioClient.entry id, market, [{side, private, volume}, ...]

# Take Order info
PeatioClient.order id, order.id

# Cancel Order or all
PeatioClient.cancel_all id
PeatioClient.cancel_ask id
PeatioClient.cancel_bid id
