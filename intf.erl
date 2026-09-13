-module(intf).
-export([new/0, add/4, remove/2, lookup/2, ref/2, name/2, list/1, broadcast/2]).

new() ->
    [].

add(Name,Ref,Pid,Intf) ->
    [{Name, Ref, Pid} | Intf].

remove(Name,Intf) ->
    lists:keydelete(Name,1,Intf).

lookup(Name,Intf) ->
    Answer = lists:keyfind(Name,1,Intf),
    case Answer of
        false -> notfound;
        {_, _, Pid} -> {ok,Pid} end.

ref(Name,Intf) ->
    Answer = lists:keyfind(Name,1,Intf),
    case Answer of
        false -> unknown;
        {_, Ref, _} -> {ok,Ref} end.

name(Ref,Intf) ->
    Answer = lists:keyfind(Ref,2,Intf),
    case Answer of
        false -> unknown;
        {Name, _, _} -> {ok,Name} end.


list([]) ->
    [];
list([{Name,_,_} | Rest]) ->
    [Name | list(Rest)].

broadcast(Message,[]) ->
    ok;
broadcast(Message, [{_,_,Pid} | Rest]) ->
    Pid ! Message,
    broadcast(Message,Rest).
    
