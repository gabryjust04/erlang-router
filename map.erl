-module(map).
-export([new/0,update/3,reachable/2,all_nodes/1]).

new() ->
    [].

update(Node,Links,Map) ->
    [{Node,Links} | lists:keydelete(Node,1,Map)].

reachable(Node,Map) ->
    case lists:keyfind(Node,1,Map) of
        {Node, Links} -> Links ;
        false -> 
            []
        end.

add_unique(Router,List) ->
    case lists:member(Router,List) of
        true -> List;
        false -> [Router | List]
    end.

add_nodes({Node,Links},Acc) ->
    Acc1 = add_unique(Node,Acc),
    lists:foldl(fun add_unique/2,Acc1,Links).



all_nodes(Map) ->
    lists:foldl(fun add_nodes/2,[],Map).