-module(test).

-export([
    auto/0,
    start/0,
    link/0,
    broadcast/0,
    update/0,
    cleanup/0,
    normal_routing/0,
    old_lsa/0,
    sequence_restart/0,
    failure_reroute/0,
    partition/0
]).

% =====================================================================
% NETWORK TOPOLOGY
%
%                   stockholm (r1)
%                        |
%                        |
%                    berlin (r2)
%                    /         \
%                   /           \
%          prague (r3)         munich (r4)
%                   \           /
%                    \         /
%                     wien (r5)
%                        |
%                        |
%                     milan (r6)
%                        |
%                        |
%                    madrid (r7)
%
%
% Initial routes:
%
% stockholm -> berlin -> munich -> wien -> milan -> madrid
%
% Alternative route if Munich dies:
%
% stockholm -> berlin -> prague -> wien -> milan -> madrid
%
% If both Munich and Prague die:
%
% stockholm/berlin     ||     wien/milan/madrid
%
% The network is partitioned.
% =====================================================================


% =====================================================================
% SETUP
% =====================================================================

start() ->
    routy:start(r1, stockholm),
    routy:start(r2, berlin),
    routy:start(r3, prague),
    routy:start(r4, munich),
    routy:start(r5, wien),
    routy:start(r6, milan),
    routy:start(r7, madrid).


link() ->
    connect(r1, stockholm, r2, berlin),
    connect(r2, berlin, r3, prague),
    connect(r2, berlin, r4, munich),
    connect(r3, prague, r5, wien),
    connect(r4, munich, r5, wien),
    connect(r5, wien, r6, milan),
    connect(r6, milan, r7, madrid),
    ok.


connect(RegA, NameA, RegB, NameB) ->
    RegA ! {add, NameB, whereis(RegB)},
    RegB ! {add, NameA, whereis(RegA)}.


broadcast() ->
    send_if_alive(r1, broadcast),
    send_if_alive(r2, broadcast),
    send_if_alive(r3, broadcast),
    send_if_alive(r4, broadcast),
    send_if_alive(r5, broadcast),
    send_if_alive(r6, broadcast),
    send_if_alive(r7, broadcast),
    ok.


update() ->
    send_if_alive(r1, update),
    send_if_alive(r2, update),
    send_if_alive(r3, update),
    send_if_alive(r4, update),
    send_if_alive(r5, update),
    send_if_alive(r6, update),
    send_if_alive(r7, update),
    ok.


% =====================================================================
% TEST 1 - NORMAL ROUTING
% =====================================================================

normal_routing() ->
    section("TEST 1 - NORMAL ROUTING"),

    io:format(
        "Sending Stockholm -> Madrid.~n"
        "Expected route: Stockholm -> Berlin -> Munich -> Wien -> Milan -> Madrid~n~n"
    ),

    r1 ! {send, madrid, normal_stockholm_madrid},

    timer:sleep(400),

    io:format(
        "~nSending Munich -> Prague.~n"
        "Expected route: Munich -> Wien -> Prague~n~n"
    ),

    r4 ! {send, prague, normal_munich_prague},

    timer:sleep(400),

    ok.


% =====================================================================
% TEST 2 - OLD LINK-STATE MESSAGE
%
% Berlin initially broadcasts sequence number 0.
%
% We then manually send Stockholm another link-state message from Berlin
% with the SAME sequence number but with intentionally incorrect links.
%
% hist:update/3 should classify it as "old".
% Therefore Stockholm's map must NOT be changed.
% =====================================================================

old_lsa() ->
    section("TEST 2 - OLD LINK-STATE MESSAGE"),

    io:format("Stockholm's knowledge about Berlin BEFORE fake LSA:~n"),
    show_node_info(r1, berlin),

    io:format(
        "~nSending fake old message:~n"
        "{links, berlin, 0, [madrid]}~n~n"
    ),

    r1 ! {links, berlin, 0, [madrid]},

    timer:sleep(300),

    io:format(
        "Stockholm's knowledge about Berlin AFTER fake LSA.~n"
        "It should be unchanged because sequence number 0 is old.~n"
    ),

    show_node_info(r1, berlin),

    ok.


% =====================================================================
% TEST 3 - SEQUENCE NUMBER AFTER ROUTER RESTART
%
% This demonstrates a limitation of the simple history mechanism.
%
% We first increase Munich's sequence number.
% Berlin remembers the latest sequence number from Munich.
%
% Munich is then killed and restarted.
% The new Munich starts again from sequence number 0.
%
% Berlin still remembers the old high sequence number, so new messages
% from Munich are considered old until the new counter exceeds the old one.
% =====================================================================

sequence_restart() ->
    section("TEST 3 - SEQUENCE NUMBER RESET AFTER RESTART"),

    io:format(
        "Increasing Munich's sequence number by broadcasting three times...~n"
    ),

    repeat_broadcast(r4, 3),

    timer:sleep(400),

    io:format("Berlin currently remembers:~n"),
    show_node_info(r2, munich),

    io:format("~nStopping Munich...~n"),

    stop_router(r4),

    timer:sleep(400),

    io:format("Restarting Munich. Its local counter starts again from 0.~n"),

    routy:start(r4, munich),

    timer:sleep(200),

    % Restore Munich's direct interfaces
    connect(r2, berlin, r4, munich),
    connect(r4, munich, r5, wien),

    timer:sleep(200),

    io:format(
        "~nNew Munich broadcasts sequence number 0.~n"
        "Berlin should reject it because it remembers a higher number.~n"
    ),

    r4 ! broadcast,

    timer:sleep(300),

    show_node_info(r2, munich),

    io:format(
        "~nNow Munich keeps broadcasting until its new sequence number~n"
        "becomes greater than Berlin's stored value.~n"
    ),

    repeat_broadcast(r4, 4),

    timer:sleep(400),

    io:format("Berlin after Munich reaches a sufficiently high counter:~n"),
    show_node_info(r2, munich),

    io:format(
        "~nRestoring a consistent network view after the restart...~n"
    ),

    broadcast(),

    timer:sleep(600),

    update(),

    timer:sleep(300),

    io:format("Testing that Munich can route again: Munich -> Prague~n"),

    r4 ! {send, prague, after_restart},

    timer:sleep(400),

    ok.


% =====================================================================
% TEST 4 - ROUTER FAILURE AND ALTERNATIVE ROUTE
%
% Munich is removed.
%
% Before link-state information and routing tables are refreshed,
% Berlin still has its old routing table and tries to use Munich.
%
% After a new broadcast + Dijkstra update, traffic should use Prague.
% =====================================================================

failure_reroute() ->
    section("TEST 4 - ROUTER FAILURE AND REROUTING"),

    io:format(
        "Stopping Munich.~n"
        "Berlin and Wien should receive a DOWN message.~n~n"
    ),

    stop_router(r4),

    timer:sleep(400),

    io:format(
        "~nTrying Stockholm -> Madrid BEFORE recomputing routing tables.~n"
        "The message is expected to be dropped because Berlin still has~n"
        "a stale route through Munich.~n~n"
    ),

    r1 ! {send, madrid, stale_route_after_munich_failure},

    timer:sleep(400),

    io:format(
        "~nBroadcasting the new topology and recomputing all routing tables...~n"
    ),

    broadcast(),

    timer:sleep(600),

    update(),

    timer:sleep(300),

    io:format(
        "~nTrying Stockholm -> Madrid again.~n"
        "Expected alternative route:~n"
        "Stockholm -> Berlin -> Prague -> Wien -> Milan -> Madrid~n~n"
    ),

    r1 ! {send, madrid, rerouted_after_munich_failure},

    timer:sleep(500),

    ok.


% =====================================================================
% TEST 5 - NETWORK PARTITION
%
% Munich is already dead from TEST 4.
% We now also kill Prague.
%
% Berlin loses both paths toward Wien, so the network is divided into:
%
%    Stockholm -- Berlin
%
%           X
%
%    Wien -- Milan -- Madrid
%
% No route from Stockholm to Madrid should exist.
% =====================================================================

partition() ->
    section("TEST 5 - NETWORK PARTITION"),

    io:format(
        "Munich is already down.~n"
        "Now stopping Prague as well...~n~n"
    ),

    stop_router(r3),

    timer:sleep(400),

    io:format(
        "Broadcasting the new topology and updating routing tables...~n"
    ),

    broadcast(),

    timer:sleep(600),

    update(),

    timer:sleep(300),

    io:format(
        "~nThe network is now partitioned:~n"
        "Stockholm -- Berlin    ||    Wien -- Milan -- Madrid~n~n"
        "Trying Stockholm -> Madrid.~n"
        "Madrid should NOT receive the message.~n~n"
    ),

    r1 ! {send, madrid, partition_test},

    timer:sleep(500),

    io:format(
        "~nTrying the opposite direction: Madrid -> Stockholm.~n"
        "Stockholm should NOT receive the message either.~n~n"
    ),

    r7 ! {send, stockholm, reverse_partition_test},

    timer:sleep(500),

    ok.


% =====================================================================
% AUTOMATED DEMONSTRATION
% =====================================================================

auto() ->
    cleanup(),
    timer:sleep(200),

    section("ROUTY AUTOMATED TEST"),

    io:format(
        "Creating seven routers and connecting the network...~n"
    ),

    start(),
    link(),

    timer:sleep(300),

    io:format("Initial link-state broadcast...~n"),

    broadcast(),

    timer:sleep(700),

    io:format("Computing initial routing tables...~n"),

    update(),

    timer:sleep(300),

    normal_routing(),
    old_lsa(),
    sequence_restart(),
    failure_reroute(),
    partition(),

    section("ALL TESTS COMPLETED"),

    io:format(
        "The network is intentionally left in the partitioned state.~n"
        "Run test:cleanup(). to stop the remaining routers.~n"
    ),

    ok.


% =====================================================================
% DEBUG / DISPLAY HELPERS
% =====================================================================

show_node_info(Router, Node) ->
    Router ! {status, self()},

    receive
        {status, {_Name, _N, Hist, _Intf, _Table, Map}} ->

            HistEntry = lists:keyfind(Node, 1, Hist),
            MapEntry = lists:keyfind(Node, 1, Map),

            io:format(
                "History entry for ~w: ~p~n"
                "Map entry for ~w:     ~p~n",
                [Node, HistEntry, Node, MapEntry]
            )

    after 1000 ->
        io:format("Could not read state from ~w~n", [Router])
    end.


section(Title) ->
    io:format(
        "~n~n"
        "================================================================~n"
        "~s~n"
        "================================================================~n",
        [Title]
    ).


repeat_broadcast(_Router, 0) ->
    ok;

repeat_broadcast(Router, N) when N > 0 ->
    send_if_alive(Router, broadcast),
    timer:sleep(100),
    repeat_broadcast(Router, N - 1).


send_if_alive(Router, Message) ->
    case whereis(Router) of
        undefined ->
            ok;
        _Pid ->
            Router ! Message,
            ok
    end.


stop_router(Router) ->
    case whereis(Router) of
        undefined ->
            ok;
        _Pid ->
            Router ! stop,
            ok
    end.


cleanup() ->
    stop_router(r1),
    stop_router(r2),
    stop_router(r3),
    stop_router(r4),
    stop_router(r5),
    stop_router(r6),
    stop_router(r7),
    ok.