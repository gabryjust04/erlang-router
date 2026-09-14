-module(dijkstra).
-export([entry/2,table/2,route/2]).

entry(Node,Sorted) ->
    case lists:keyfind(Node,1,Sorted) of
        {_,Hop,_} -> Hop;
        false -> 0 end.


insert({Node,N,Gateway},[]) ->
    [{Node,N,Gateway}|[]];
insert({Node,N,Gateway}, [{C,L,G}| Rest]) when N=<L ->
    [{Node,N,Gateway},{C,L,G}|Rest];
insert({Node,N,Gateway}, [{C,L,G}| Rest]) when N>L ->
    [{C,L,G} | insert({Node,N,Gateway},Rest)].




replace(Node,N,Gateway,Sorted) ->
    Cleaned = lists:keydelete(Node,1,Sorted),
    insert({Node,N,Gateway},Cleaned).

update(Node,N,Gateway,Sorted) ->
    X = entry(Node,Sorted),
    case N<X of
        true -> replace(Node,N,Gateway,Sorted);
        false -> Sorted end.


gateway_entries([]) ->
    [];
gateway_entries([Gateway | Rest]) ->
    [{Gateway,0,Gateway}| gateway_entries(Rest)].

other_entries([],Gateways) -> 
    [];
other_entries([X | Rest],Gateways) ->
    case lists:member(X,Gateways) of
        true ->
            other_entries(Rest,Gateways);
        false -> 
            [{X, inf, unknown}| other_entries(Rest,Gateways)] end.
    
update_neighbors([],N,Gateway,Sorted) ->
    Sorted;
update_neighbors([Next | Neighbors], N,Gateway,Sorted) ->
    UpdateSorted = update(Next,N+1,Gateway,Sorted),
    update_neighbors(Neighbors, N,Gateway,UpdateSorted).


iterate([],Map,Table) ->
    Table;
iterate([{_,inf,_}| Sorted],Map,Table)->
    Table;
iterate([{Node,N,Gateway}| Sorted],Map,Table) ->
    Table1 = [{Node,Gateway} | Table],
    Neighbors = map:reachable(Node,Map),
    UpdateSorted = update_neighbors(Neighbors,N,Gateway,Sorted),
    iterate(UpdateSorted,Map,Table1).


table(Gateways,Map) ->
    AllNodes = map:all_nodes(Map),
    GwList = gateway_entries(Gateways),
    InitialSorted = GwList ++ other_entries(AllNodes,Gateways),
    iterate(InitialSorted,Map,[]).

route(Node,Table) ->
    case lists:keyfind(Node,1,Table) of
        {Node, Gateway} -> {ok, Gateway};
        false -> notfound end.

    
