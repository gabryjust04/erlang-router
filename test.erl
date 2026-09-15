-module(test).

-export([
    auto/0, start/0, link/0, broadcast/0, update/0, cleanup/0,
    normal_routing/0, old_lsa/0, sequence_restart/0, failure_reroute/0, partition/0
]).

% =====================================================================
% NETWORK TOPOLOGY
%
%                   stockholm (r1)
%                         |
%                         |
%                     berlin (r2)
%                     /         \
%                    /           \
%           prague (r3)         munich (r4)
%                    \           /
%                     \         /
%                      wien (r5)
%                         |
%                         |
%                      milan (r6)
%                         |
%                         |
%                     madrid (r7)
%
% Initial routes:
% stockholm -> berlin -> munich -> wien -> milan -> madrid
%
% Alternative route if Munich dies:
% stockholm -> berlin -> prague -> wien -> milan -> madrid
%
% If both Munich and Prague die:
% stockholm/berlin     ||     wien/milan/madrid (network partitioned)
% =====================================================================

routers() ->
    [{r1, stockholm}, {r2, berlin}, {r3, prague}, {r4, munich},
     {r5, wien}, {r6, milan}, {r7, madrid}].

router_names() -> [r1, r2, r3, r4, r5, r6, r7].

start() ->
    [routy:start(Reg, Name) || {Reg, Name} <- routers()],
    ok.

link() ->
    Links = [
        {r1, stockholm, r2, berlin}, {r2, berlin, r3, prague},
        {r2, berlin, r4, munich},    {r3, prague, r5, wien},
        {r4, munich, r5, wien},      {r5, wien, r6, milan},
        {r6, milan, r7, madrid}
    ],
    [connect(Ra, Na, Rb, Nb) || {Ra, Na, Rb, Nb} <- Links],
    ok.

connect(RegA, NameA, RegB, NameB) ->
    RegA ! {add, NameB, whereis(RegB)},
    RegB ! {add, NameA, whereis(RegA)}.

broadcast() -> [send_if_alive(R, broadcast) || R <- router_names()], ok.
update()    -> [send_if_alive(R, update) || R <- router_names()], ok.

% --- Tests ---

normal_routing() ->
    section("TEST 1 - NORMAL ROUTING"),
    io:format("Route: stockholm -> madrid~n"),
    r1 ! {send, madrid, normal_stockholm_madrid},
    timer:sleep(400),
    io:format("Route: munich -> prague~n"),
    r4 ! {send, prague, normal_munich_prague},
    timer:sleep(400),
    ok.

old_lsa() ->
    section("TEST 2 - OLD LINK-STATE MESSAGE"),
    io:format("Stockholm state BEFORE fake LSA:~n"),
    show_node_info(r1, berlin),
    io:format("Sending duplicate seq=0 LSA from berlin...~n"),
    r1 ! {links, berlin, 0, [madrid]},
    timer:sleep(300),
    io:format("Stockholm state AFTER (should be unchanged):~n"),
    show_node_info(r1, berlin),
    ok.

sequence_restart() ->
    section("TEST 3 - SEQUENCE RESTART"),
    io:format("Bumping Munich seq number...~n"),
    repeat_broadcast(r4, 3),
    timer:sleep(400),
    show_node_info(r2, munich),
    
    io:format("Restarting Munich (seq counter resets to 0)...~n"),
    stop_router(r4),
    timer:sleep(400),
    routy:start(r4, munich),
    timer:sleep(200),
    connect(r2, berlin, r4, munich),
    connect(r4, munich, r5, wien),
    timer:sleep(200),

    io:format("Broadcast seq=0 (Berlin should reject):~n"),
    r4 ! broadcast,
    timer:sleep(300),
    show_node_info(r2, munich),

    io:format("Munich broadcasts until exceeding Berlin's cached counter:~n"),
    repeat_broadcast(r4, 4),
    timer:sleep(400),
    show_node_info(r2, munich),

    broadcast(), timer:sleep(600),
    update(),    timer:sleep(300),
    r4 ! {send, prague, after_restart},
    timer:sleep(400),
    ok.

failure_reroute() ->
    section("TEST 4 - ROUTER FAILURE AND REROUTE"),
    io:format("Stopping Munich...~n"),
    stop_router(r4),
    timer:sleep(400),
    io:format("Testing stale path (should drop):~n"),
    r1 ! {send, madrid, stale_route_after_munich_failure},
    timer:sleep(400),

    io:format("Reconverging topology via Prague...~n"),
    broadcast(), timer:sleep(600),
    update(),    timer:sleep(300),
    r1 ! {send, madrid, rerouted_after_munich_failure},
    timer:sleep(500),
    ok.

partition() ->
    section("TEST 5 - NETWORK PARTITION"),
    io:format("Stopping Prague (Munich already down)...~n"),
    stop_router(r3),
    timer:sleep(400),
    broadcast(), timer:sleep(600),
    update(),    timer:sleep(300),

    io:format("Testing Stockholm -> Madrid (should fail):~n"),
    r1 ! {send, madrid, partition_test},
    timer:sleep(500),
    io:format("Testing Madrid -> Stockholm (should fail):~n"),
    r7 ! {send, stockholm, reverse_partition_test},
    timer:sleep(500),
    ok.

auto() ->
    cleanup(),
    timer:sleep(200),
    section("ROUTY AUTOMATED TEST"),
    start(), link(),
    timer:sleep(300),
    broadcast(), timer:sleep(700),
    update(),    timer:sleep(300),
    normal_routing(),
    old_lsa(),
    sequence_restart(),
    failure_reroute(),
    partition(),
    section("ALL TESTS COMPLETED"),
    ok.

% --- Helpers ---

show_node_info(Router, Node) ->
    Router ! {status, self()},
    receive
        {status, {_Name, _N, Hist, _Intf, _Table, Map}} ->
            io:format("~w info -> Hist: ~p | Map: ~p~n",
                      [Node, lists:keyfind(Node, 1, Hist), lists:keyfind(Node, 1, Map)])
    after 1000 ->
        io:format("Timeout reading state from ~w~n", [Router])
    end.

section(Title) ->
    io:format("~n=== ~s ===~n", [Title]).

repeat_broadcast(_Router, 0) -> ok;
repeat_broadcast(Router, N) when N > 0 ->
    send_if_alive(Router, broadcast),
    timer:sleep(100),
    repeat_broadcast(Router, N - 1).

send_if_alive(Router, Message) ->
    case whereis(Router) of
        undefined -> ok;
        Pid       -> Pid ! Message, ok
    end.

stop_router(Router) ->
    send_if_alive(Router, stop).

cleanup() ->
    [stop_router(R) || R <- router_names()],
    ok.