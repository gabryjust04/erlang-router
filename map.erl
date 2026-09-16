-module(map).
-export([new/0, update/3, reachable/2, all_nodes/1]).

new() ->
    [].

update(Node, Links, Map) ->
    [{Node, Links} | lists:keydelete(Node, 1, Map)].

reachable(Node, Map) ->
    case lists:keyfind(Node, 1, Map) of
        {Node, Links} ->
            Links;
        false ->
            []
    end.

all_nodes(Map) ->
    Acc = lists:foldl(
        fun({Node, Links}, A) ->
            lists:foldl(fun add/2, A, lists:reverse(Links) ++ [Node])
        end,
        [],
        Map),
    lists:reverse(Acc).
 
add(Node, Acc) ->
    case lists:member(Node, Acc) of
        true  -> Acc;
        false -> [Node | Acc]
    end.