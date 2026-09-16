-module(hist).
-export([new/1, update/3]).

new(Name) ->
    [{Name, inf}].

update(Node, N, History) ->
    case lists:keyfind(Node, 1, History) of
        {Node, Highest} when N =< Highest ->
            old;
        {Node, _Highest} ->
            {new, lists:keyreplace(Node, 1, History, {Node, N})};
        false ->
            {new, [{Node, N} | History]}
    end.