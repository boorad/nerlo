
%% @doc Application module for Erlang/Java bridge..
%%
%% @author Ingo Schramm

-module(neo4j_app).
-behaviour(application).
-export([start/0,start/2,prep_stop/1,stop/1,stop/0]).

-author("Ingo Schramm").

-include_lib("eunit/include/eunit.hrl").

-define(APPNAME, neo4j).

start() ->
    application:start(?APPNAME).

stop() ->
    application:stop(?APPNAME).

start(Type, Args) ->
    ej_log:info("starting; type: ~p args: ~p", [Type,Args]),
    case Type of
        normal   -> neo4j_sup:start_link([]);
        takeover -> ok;
        failover -> ok
    end.

prep_stop(State) ->
    ej_log:info("prepare stopping with state: ~p", [State]),
    neo4j_srv:stop(),
    timer:sleep(1000),
    ok.

stop(State) ->
    ej_log:info("stopping with state: ~p", [State]),
    ok.

%% getenv(K,Def) ->
%%     case application:get_env(?APPNAME,K) of
%%         undefined -> Def;
%%         {ok,Val}  -> Val
%%     end.
