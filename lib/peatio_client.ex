defmodule PeatioClient do
  import PeatioClient.Server

  #############################################################################
  ### PEATIO Public API
  #############################################################################

  def ticker(market) do
    body = build_api_request("/tickers/#{market}") |> gogogo!
    ticker = body |> Map.get("ticker") |> Enum.reduce %{}, fn
      ({key, val}, acc) ->
        key = key |> filter_key |> String.to_atom
        val = val |> Decimal.new
        Map.put(acc, key, val)
    end
    Map.put ticker, :at, body["at"]
  end

  def trades(market) do
    body = build_api_request("/trades") |> set_payload([market: market]) |> gogogo!

    body |> Enum.map fn
      (trade) ->
        %{
          id: trade["id"], 
          at: trade["at"], 
          price: Decimal.new(trade["price"]), 
          volume: Decimal.new(trade["volume"]),
          side: String.to_atom(trade["side"]),
          funds: Decimal.new(trade["funds"])
        }
    end
  end

  #############################################################################
  ### PEATIO Private API
  #############################################################################

  def me(account) do
    GenServer.call account_name(account), :members_me
  end

  def bid(account, market, orders) do
    orders = orders |> Enum.map fn {p, v} -> {:bid, p, v} end
    entry(account, market, orders)
  end

  def ask(account, market, orders) do
    orders = orders |> Enum.map fn {p, v} -> {:ask, p, v} end
    entry(account, market, orders)
  end

  def entry(account, market, orders) do
    orders = orders |> Enum.map fn
      ({:ask, price, volume}) ->
        %{price: price, side: :sell, volume: volume}
      ({:bid, price, volume}) ->
        %{price: price, side: :buy, volume: volume}
    end

    GenServer.call(account_name(account), {:orders_multi, market, orders})
    |> Enum.map &convert_order/1
  end

  def orders(account, market) do
    GenServer.call(account_name(account), {:orders, market})
    |> Enum.map &convert_order/1
  end

  def order(account, market, order_id) do
    GenServer.call(account_name(account), {:order, market, order_id})
    |> convert_order
  end

  def cancel(account, id) when is_integer(id) do
    GenServer.call(account_name(account), {:orders_cancel, id})
    |> convert_order
  end

  def cancel_all(account) do
    GenServer.call(account_name(account), {:orders_cancel, :all})
    |> Enum.map &convert_order/1
  end

  def cancel_ask(account) do
    GenServer.call(account_name(account), {:orders_cancel, :ask})
    |> Enum.map &convert_order/1
  end

  def cancel_bid(account) do
    GenServer.call(account_name(account), {:orders_cancel, :bid})
    |> Enum.map &convert_order/1
  end

  #############################################################################

  defp filter_key(key) do
    case key do
      "buy"  -> "bid"
      "sell" -> "ask"
      _      -> key
    end
  end

  defp filter_order_val(key, val) do
    case key do
      "avg_price" -> Decimal.new(val)
      "price" -> Decimal.new(val)
      "executed_volume" -> Decimal.new(val)
      "remaining_volume" -> Decimal.new(val)
      "volume" -> Decimal.new(val)
      "side" -> String.to_atom(filter_key(val))
      "market" -> String.to_atom(val)
      "state" -> String.to_atom(val)
      _ -> val
    end
  end

  defp convert_order(order) when is_map(order) do
    for {key, val} <- order, into: %{}, do: {String.to_atom(key), filter_order_val(key, val)}
  end
end
