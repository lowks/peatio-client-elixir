require Logger 

defmodule PeatioClient do
  use HTTPoison.Base
  use GenServer

  #############################################################################
  ### PEATIO Public API
  #############################################################################

  def ticker(market) do
    body = build_api_request("/tickers/#{market}.json") |> gogogo!
    ticker = body |> Map.get("ticker") |> Enum.reduce %{}, fn
      ({key, val}, acc) ->
        key = key |> filter_key |> String.to_atom
        val = val |> Decimal.new
        Map.put(acc, key, val)
    end
    Map.put ticker, :at, body["at"]
  end

  def trades(market) do
    body = build_api_request("/trades.json") |> set_payload([market: market]) |> gogogo!

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

    GenServer.call account_name(account), {:orders_multi, market, orders}
  end

  def cancel(account, id) when is_integer(id) do
    GenServer.call account_name(account), {:orders_cancel, id}
  end

  def cancel_all(account) do
    GenServer.call account_name(account), {:orders_cancel, :all}
  end

  def cancel_ask(account) do
    GenServer.call account_name(account), {:orders_cancel, :ask}
  end

  def cancel_bid(account) do
    GenServer.call account_name(account), {:orders_cancel, :bid}
  end

  #############################################################################
  ### GenServer Callback
  #############################################################################

  def start_link(account, key, secret) do
    opts  = [name: account_name(account)]
    GenServer.start_link(__MODULE__, %{key: key, secret: secret}, opts)
  end

  def init(auth) do
    {:ok, %{auth: auth}}
  end

  def handle_call(:members_me, _, state = %{auth: auth}) do
    body = build_api_request("/members/me")
            |> sign_request(auth)
            |> gogogo!
    {:reply, body, state} 
  end

  def handle_call({:orders_multi, market, orders}, _, state = %{auth: auth}) do
    payload = [market: market]

    payload = orders |> Enum.reduce payload, fn
      (%{price: p, side: s, volume: v}, acc) -> 
        acc = acc ++ [{:"orders[][price]",  p}]
        acc = acc ++ [{:"orders[][volume]", v}]
        acc ++ [{:"orders[][side]",   s}]
    end

    body = build_api_request("/orders/multi", :post)
            |> set_payload(payload) 
            |> sign_request(auth)
            |> gogogo!

    {:reply, body, state}
  end

  def handle_call({:orders_cancel, id}, _, state = %{auth: auth}) when is_integer(id) do
    body = build_api_request("/order/delete", :post)
            |> set_payload([id: id]) 
            |> sign_request(auth)
            |> gogogo!

    {:reply, body, state}
  end

  def handle_call({:orders_cancel, side}, _, state = %{auth: auth}) do
    payload = case side do
      :ask -> [side: "sell"]
      :bid -> [side: "buy"]
      _ -> []
    end

    body = build_api_request("/orders/clear", :post)
            |> set_payload(payload) 
            |> sign_request(auth)
            |> gogogo!

    {:reply, body, state}
  end

  #############################################################################
  ### HTTPoison Callback and Helper
  #############################################################################

  defp process_url(url) do
    "https://yunbi.com" <> url
  end

  defp process_response_body(body) do
    body |> Poison.decode!
  end

  #############################################################################
  ### Helper and Private
  #############################################################################

  defp api_uri(path) do
    "/api/v2" <> path
  end

  defp filter_key(key) do
    case key do
      "buy"  -> "bid"
      "sell" -> "ask"
      _      -> key
    end
  end

  def account_name(account) do
    String.to_atom "#{account}.api.peatio.com"
  end

  defp build_api_request(path, verb \\ :get, tonce \\ nil) when verb == :get or verb == :post do
    uri = api_uri(path)
    tonce = tonce || :os.system_time(:milli_seconds) 
    %{uri: uri, tonce: tonce, verb: verb, payload: nil}
  end

  defp set_payload(req = %{payload: nil}, payload) do
    %{req | payload: payload}
  end

  defp set_payload(req = %{payload: payload}, new_payload) when is_list(payload) do
    %{req | payload: payload ++ new_payload}
  end

  # REF: https://yunbi.com/documents/api_v2#!/members/GET_version_members_me_format
  defp sign_request(req, %{key: key, secret: secret}) do
    verb = req.verb |> Atom.to_string |> String.upcase

    payload = (req.payload || [])
              |> Dict.put(:access_key, key)
              |> Dict.put(:tonce, req.tonce)

    query = Enum.sort(payload) |> Enum.map_join("&", fn {k, v} -> "#{k}=#{v}" end)

    to_sign   = [verb, req.uri, query] |> Enum.join("|")
    signature = :crypto.hmac(:sha256, secret, to_sign) |> Base.encode16 |> String.downcase

    %{req | payload: Dict.put(payload, :signature, signature)}
  end

  defp gogogo!(%{uri: uri, verb: :get, payload: payload}) when is_list(payload) do
    Logger.debug "GET #{uri} #{inspect payload}"
    payload = payload |> Enum.map(fn({k, v}) -> "#{k}=#{v}" end) |> Enum.join("&")
    get!(uri <> "?" <> payload).body
  end

  defp gogogo!(%{uri: uri, verb: :get, payload: _}) do
    Logger.debug "GET #{uri}"
    get!(uri).body
  end

  defp gogogo!(%{uri: uri, verb: :post, payload: payload}) do
    Logger.debug "POST #{uri} #{inspect payload}"
    post!(uri, {:form, payload}).body
  end
end
