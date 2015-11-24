require Logger 

defmodule PeatioClient.Server do
  use HTTPoison.Base
  use GenServer
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

  def handle_call({:orders, market}, _, state = %{auth: auth}) do
    payload = [market: market]

    body = build_api_request("/orders")
            |> set_payload(payload) 
            |> sign_request(auth)
            |> gogogo!

    {:reply, body, state}
  end
  
  def handle_call({:order, order_id}, _, state = %{auth: auth}) do
    payload = [id: order_id]

    body = build_api_request("/order")
            |> set_payload(payload) 
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

  def handle_cast({:orders_cancel, id}, state = %{auth: auth}) when is_integer(id) do
    build_api_request("/order/delete", :post)
    |> set_payload([id: id]) 
    |> sign_request(auth)
    |> gogogo!

    {:noreply, state}
  end

  def handle_cast({:orders_cancel, side}, state = %{auth: auth}) do
    payload = case side do
      :ask -> [side: "sell"]
      :bid -> [side: "buy"]
      _ -> []
    end

    build_api_request("/orders/clear", :post)
    |> set_payload(payload) 
    |> sign_request(auth)
    |> gogogo!

    {:noreply, state}
  end

  #############################################################################
  ### HTTPoison Callback and Helper
  #############################################################################

  defp process_url(url) do
    host = Application.get_env(:peatio_client, :host) || System.get_env("HOST") || "https://app.peatio.com"
    host <> url
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

  def account_name(account) do
    String.to_atom "#{account}.api.peatio.com"
  end

  def build_api_request(path, verb \\ :get, tonce \\ nil) when verb == :get or verb == :post do
    uri = api_uri(path)
    tonce = tonce || :os.system_time(:milli_seconds) 
    %{uri: uri, tonce: tonce, verb: verb, payload: nil}
  end

  def set_payload(req = %{payload: nil}, payload) do
    %{req | payload: payload}
  end

  def set_payload(req = %{payload: payload}, new_payload) when is_list(payload) do
    %{req | payload: payload ++ new_payload}
  end

  # REF: https://app.peatio.com/documents/api_v2#!/members/GET_version_members_me_format
  def sign_request(req, %{key: key, secret: secret}) do
    verb = req.verb |> Atom.to_string |> String.upcase

    payload = (req.payload || [])
              |> Dict.put(:access_key, key)
              |> Dict.put(:tonce, req.tonce)

    query = Enum.sort(payload) |> Enum.map_join("&", fn {k, v} -> "#{k}=#{v}" end)

    to_sign   = [verb, req.uri, query] |> Enum.join("|")
    signature = :crypto.hmac(:sha256, secret, to_sign) |> Base.encode16 |> String.downcase

    %{req | payload: Dict.put(payload, :signature, signature)}
  end

  def gogogo!(%{uri: uri, verb: :get, payload: payload}) when is_list(payload) do
    Logger.debug "GET #{uri} #{inspect payload}"
    payload = payload |> Enum.map(fn({k, v}) -> "#{k}=#{v}" end) |> Enum.join("&")
    get!(uri <> "?" <> payload).body
  end

  def gogogo!(%{uri: uri, verb: :get, payload: _}) do
    Logger.debug "GET #{uri}"
    get!(uri).body
  end

  def gogogo!(%{uri: uri, verb: :post, payload: payload}) do
    Logger.debug "POST #{uri} #{inspect payload}"
    post!(uri, {:form, payload}).body
  end
end

