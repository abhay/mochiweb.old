%% @author Abhay Kumar <abhay@opensynapse.net>
%% @copyright 2008 Abhay Kumar

%% @doc Generic RPC Implementation. Only supports JSON-RPC for now and does not support sessions.

-module(json_rpc).
-author("Abhay Kumar <abhay@opensynapse.net>").

-export([handler/2]).
-export([test/0]).

%% @spec handler(Request, {Module, Function}) -> MochiWebResponse
%% @doc Use this function in order to process RPC calls from the outside.
%% Write your own function to process the Erlang representation of the 
%% RPC objects and pass it into this function as a {Module, Function}
%% tuple.
handler(Req, ModFun) ->
  case acceptable_request(Req) of
    ok ->
      handle_request(Req, ModFun);
    {status, StatusCode, Reason} ->
      send(Req, StatusCode, encode_error(Reason, null))
    end.

%% @doc run all the tests for this module
test() ->
  test_acceptable_request(),
  test_decode_request_body(),
  ok.

acceptable_request(Req) ->
  case {Req:get(method), Req:get(version)} of
    {'POST', {1, 0}} -> ok;
    {'POST', {1, 1}} -> ok;
    {'POST', HTTPVersion} -> {status, 505, lists:flatten(io_lib:format("HTTP Version ~p is not supported.", [HTTPVersion]))};
    {Method, {1, 1}} -> {status, 501, lists:flatten(io_lib:format("The ~p method has not been implemented.", [Method]))};
    _ -> {status, 400, "Bad Request."}
  end.

handle_request(Req, {Mod, Fun}) ->
    Body = binary_to_list(Req:recv_body()),
    case decode_request_body(Body) of
      {ok, Decoded, ID} ->
        case Mod:Fun(Req, Decoded) of
          {'EXIT', Reason} ->
            send(Req, 500, encode_error(Reason, ID));
          {error, Reason} ->
            send(Req, 500, encode_error(Reason, ID));
          {result, Result} ->
            send(Req, 200, encode_result(Result, ID))
          end;
      {error, Reason} ->
        send(Req, 500, encode_error(Reason, null))
    end.

decode_request_body(Body) ->
  try
    JsonObj = mochijson:decode(Body),
    {ok, {call, list_to_atom(fetch(JsonObj, method)), fetch(JsonObj, params)}, fetch(JsonObj, id)}
  catch
     _:_ -> {error, "Error decoding request."}
  end.

encode_error(Reason, ID) -> lists:flatten(mochijson:encode({struct, [{id, ID}, {error, Reason}, {result, null}]})).

encode_result(Result, ID) ->
  try
    lists:flatten(mochijson:encode({struct, [{id, ID}, {error, null}, {result, Result}]}))
  catch
    _:_ -> encode_error("Error encoding response.", ID)
  end.

send(Req, StatusCode, JsonStr) ->
  Req:respond({StatusCode, [{'Content-Type', "application/json"}], JsonStr}).

fetch(JsonObj, Key) when is_atom(Key) ->
  fetch(JsonObj, atom_to_list(Key));
fetch({struct, List}, Key) when is_list(List) ->
  case lists:keysearch(Key, 1, List) of
    {value, {Key, Value}} -> Value;
    _ -> []
  end.

test_acceptable_request() ->
    test_each_acceptable_request(tuples_for_test_acceptable_request()).

test_each_acceptable_request([]) -> ok;
test_each_acceptable_request([{ShouldReceive, WillAsk}|Rest]) ->
  true = ShouldReceive == acceptable_request(mochiweb:new_request(WillAsk)),
  test_each_acceptable_request(Rest).

tuples_for_test_acceptable_request() ->
  [
    {ok, {foo, {'POST', {abs_path, "/"}, {1,0}}, [{'Content-Type', "application/json"}]}},
    {ok, {foo, {'POST', {abs_path, "/"}, {1,1}}, [{'Content-Type', "application/json"}]}},
    {{status, 505, "HTTP Version {5,0} is not supported."}, {foo, {'POST', {abs_path, "/"}, {5,0}}, [{'Content-Type', "application/json"}]}},
    {{status, 501, "The 'PUT' method has not been implemented."}, {foo, {'PUT', {abs_path, "/"}, {1, 1}}, [{'Content-Type', "application/json"}]}},
    {{status, 400, "Bad Request."}, {foo, {'PUT', {abs_path, "/"}, {5,0}}, [{'Content-Type', "application/json"}]}}
  ].

test_decode_request_body() ->
  test_decode_request_good(),
  test_decode_request_bad(),
  ok.

test_decode_request_good() ->
  GoodJsonStr = "{\"id\":\"foobarbaz\",\"method\":\"foo\",\"params\":{\"bar\":{\"baz\":[1,2,3]}}}",
  {ok, {call, foo, {struct, [{"bar", {struct, [{"baz", {array, [1, 2, 3]}}]}}]}}, "foobarbaz"} = decode_request_body(GoodJsonStr),
  ok.

test_decode_request_bad() ->
  BadJsonStr = "{\"id\":\"foobarbaz\"params\":{\"bar\":\"baz\"}}",
  {error, "Error decoding request."} = decode_request_body(BadJsonStr),
  ok.
