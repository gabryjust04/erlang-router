-module(dijkstra).
-export([table/2, route/2]).

entry(Node, Sorted) ->
    case lists:keyfind(Node, 1, Sorted) of
        {Node, N, _Gateway} ->
            N;
        false ->
            0
    end.

replace(Node, N, Gateway, Sorted) ->
    Rest = lists:keydelete(Node, 1, Sorted),
    lists:keysort(2, [{Node, N, Gateway} | Rest]).

update(Node, N, Gateway, Sorted) ->
    case N < entry(Node, Sorted) of
        true ->
            replace(Node, N, Gateway, Sorted);
        false ->
            Sorted
    end.

iterate([], _Map, Table) ->
    Table;
iterate([{_Node, inf, _Gateway} | _Rest], _Map, Table) ->
    Table;
iterate([{Node, N, Gateway} | Rest], Map, Table) ->
    Reachable = map:reachable(Node, Map),
    Sorted = lists:foldl(
        fun(Neighbor, Acc) ->
            update(Neighbor, N + 1, Gateway, Acc)
        end,
        Rest,
        Reachable),
    iterate(Sorted, Map, Table ++ [{Node, Gateway}]).

table(Gateways, Map) ->
    Nodes = lists:usort(Gateways ++ map:all_nodes(Map)),
    Initial = [init_entry(Node, Gateways) || Node <- Nodes],
    Sorted = lists:keysort(2, Initial),
    iterate(Sorted, Map, []).

init_entry(Node, Gateways) ->
    case lists:member(Node, Gateways) of
        true ->
            {Node, 0, Node};
        false ->
            {Node, inf, unknown}
    end.

route(Node, Table) ->
    case lists:keyfind(Node, 1, Table) of
        {Node, Gateway} ->
            {ok, Gateway};
        false ->
            notfound
    end.