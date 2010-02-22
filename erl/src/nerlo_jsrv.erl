%% @doc This is the  Erlang server maintaining connections
%% to the hidden java node.
%%
%% If nerlo.jar in ../java/dist, then
%% <pre>
%% (shell@host)1> {ok,Pid} = nerlo_jsrv:start().
%% (shell@host)2> nerlo_jsrv:send(job).
%% (shell@host)3> nerlo_jsrv:stop().
%% </pre>
%% @author Ingo Schramm

-module(nerlo_jsrv).
-behaviour(gen_server).

% public interface
-export([job/1,send/1]).
-export([start/0, start/1, start/2, start_link/0, start_link/1, start_link/2, stop/0]).

% gen_server exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-author("Ingo Schramm").

-include("global.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(DEFAULT_N, erlang:system_info(schedulers_online) * 2).
-define(SRVNAME, ?MODULE).
-define(STARTSPEC, {local, ?SRVNAME}).
-define(PEERNAME, jnode).
-define(PEERSTR, atom_to_list(?PEERNAME)).
-define(NERLOMSG(Body), {self(), {Body}}).
-define(BINDIR, "./bin").
-define(JNODEBIN, "jnode").

-record(jsrv, {workers = []
              ,worker  = no
              ,n       = 0
              ,peer    = null
              ,bindir  = ?BINDIR
              ,stopping= false
              }).

start() ->
    start(?DEFAULT_N).

start(N) ->
    gen_server:start(?STARTSPEC, ?MODULE, #jsrv{n=N}, []).

start(N,Bindir) ->
    gen_server:start(?STARTSPEC, ?MODULE, #jsrv{n=N,bindir=Bindir}, []).

start_link() ->
    start_link(?DEFAULT_N). 
    
start_link(N) ->
    gen_server:start_link(?STARTSPEC, ?MODULE, #jsrv{n=N}, []).

start_link(N,Bindir) ->
    gen_server:start_link(?STARTSPEC, ?MODULE, #jsrv{n=N,bindir=Bindir}, []).

stop() ->
    gen_server:cast(?SRVNAME, {'STOP'}).

% @doc Send a message to the peer.
send(Msg) ->
    gen_server:call(?SRVNAME, {send, Msg}).

job(Spec) ->
    gen_server:call(?SRVNAME, {job, Spec}).   

   
% @hidden    
init(S) ->
    S1 =
    case S#jsrv.worker of
        yes -> S;
        no  ->
            log:debug(self(), "cwd: ~p", [file:get_cwd()]),
            timer:start(),
            Peer    = handshake(S#jsrv.bindir),
            S2 = S#jsrv{peer=Peer},
            Workers =
            lists:foldl(fun(_I,Acc) -> 
                            case start_worker(S2) of
                                {ok,Pid} -> [Pid|Acc];
                                _Any     -> Acc
                            end
                        end, [], lists:seq(1,S#jsrv.n)),
            S2#jsrv{workers=Workers}
    end,
    log:info(self(), "~p initialized with state ~w", [?MODULE, S1]),
    {ok,S1}.

% @hidden     
handle_call({job,Spec},From,S) ->
    {W, L} = f:lrot(S#jsrv.workers),
    gen_server:cast(W,{job,From,Spec}),
    {noreply, S#jsrv{workers=L}};
handle_call({send,Msg},From,S) ->
    {W, L} = f:lrot(S#jsrv.workers),
    gen_server:cast(W,{send,From,Msg}),
    {noreply, S#jsrv{workers=L}};
handle_call(Msg,From,S) ->
    log:warn(self(), "Cannot understand call from ~p: ~p", [From,Msg]),
    {reply, {error, unknown_msg}, S}.

% @hidden
handle_cast({job,From,Spec}, S) ->
    Result = send_job(S#jsrv.peer,Spec),
    gen_server:reply(From, Result),
    {noreply, S};
handle_cast({send,From,Msg}, S) ->
    Result = send_peer(S#jsrv.peer,Msg),
    gen_server:reply(From, Result),
    {noreply, S};
handle_cast({'STOP'}, S) ->
    case S#jsrv.worker of
        yes -> nop;
        no  -> shutdown(S#jsrv.peer,S)
    end,
    timer:send_after(500,?NERLOMSG(bye)),
    log:info(self(),"stopping with state: ~w", [S]),
    {noreply, S#jsrv{stopping=true}};
    %{stop, normal, S};
handle_cast(Msg,S) ->
    log:info(self(),"cannot handle cast: ~p", [Msg]),
    {noreply, S}.

% @hidden
handle_info({Pid,{handshake}},S) ->
    log:debug(self(), "got handshake from: ~p", [Pid]),
    {noreply, S#jsrv{peer=Pid}};
handle_info({Port,{data,"\n"}},S) when is_port(Port) ->
    {noreply,S};
handle_info({Port,{data,Msg}},S) when is_port(Port) ->
    log:info(self(),"port says: ~p", [Msg]),
    {noreply,S};
handle_info({From,{bye}},S) ->
    case S#jsrv.stopping of
        false -> {noreply,S};
        true  -> 
            log:info(self(), "bye, triggerd from: ~p", [From]),
            {stop, normal, S}
    end;
handle_info(Msg,S) ->
    log:info(self(),"info: ~p", [Msg]),
    {noreply,S}.

% @hidden     
terminate(_Reason,S) ->
    {noreply, S}.

% @hidden     
code_change(_OldVsn, S, _Extra) -> 
    {ok, S}.


%% ------ PRIVATE PARTS -----

handshake(Bindir) ->
    Args = "-peer " ++ atom_to_list(node())
         ++ " -sname " ++ ?PEERSTR
         ++ " -cookie " ++ atom_to_list(erlang:get_cookie()),
    Cmd  = Bindir ++ "/" ++ ?JNODEBIN ++ " " ++ Args ++ " &",
    log:info(self(), "starting JNode: ~p", [Cmd]),
    erlang:open_port({spawn, Cmd},[]),
    timer:sleep(500),
    {ok, Hostname} = inet:gethostname(),
    Peer = {?PEERNAME,list_to_atom(?PEERSTR ++ "@" ++ Hostname)},
    log:info(self(), "send handshake to: ~p", [Peer]),
    send_peer(Peer, handshake),
    Peer.

send_job(Peer,Spec) ->
    send_peer(Peer,{job, Spec}).

send_peer(Peer,Msg) ->
    Peer ! ?NERLOMSG(Msg).

start_worker(S) ->
    gen_server:start(?MODULE, S#jsrv{worker=yes}, []).
    
shutdown(Peer,S) ->
    send_peer(Peer, die),
    lists:map(fun(W) -> W ! {'STOP'} end, S#jsrv.workers).

   
%% ------ TESTS ------

start_stop_test() ->
    {ok,Pid} = start(2,"../bin"),
    ?assert(is_pid(Pid)),
    stop().

%job_test() ->
%    start(),
%    Spec = test,
%    {Pid1,Spec} = job(Spec),
%    {Pid2,Spec} = job(Spec),
%    ?assertNot(Pid1 =:= Pid2),
%    stop().





  
