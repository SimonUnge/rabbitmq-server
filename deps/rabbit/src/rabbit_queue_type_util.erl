%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%
%% Copyright (c) 2007-2024 Broadcom. All Rights Reserved. The term “Broadcom” refers to Broadcom Inc. and/or its subsidiaries. All rights reserved.
%%

-module(rabbit_queue_type_util).

-export([args_policy_lookup/3,
         qname_to_internal_name/1,
         check_auto_delete/1,
         check_exclusive/1,
         check_non_durable/1,
         run_checks/2,
         grow/6,
         erpc_call/5]).

-include_lib("rabbit_common/include/rabbit.hrl").
-include("amqqueue.hrl").

args_policy_lookup(Name, Resolve, Q) when ?is_amqqueue(Q) ->
    Args = amqqueue:get_arguments(Q),
    AName = <<"x-", Name/binary>>,
    case {rabbit_policy:get(Name, Q), rabbit_misc:table_lookup(Args, AName)} of
        {undefined, undefined}       -> undefined;
        {undefined, {_Type, Val}}    -> Val;
        {Val,       undefined}       -> Val;
        {PolVal,    {_Type, ArgVal}} -> Resolve(PolVal, ArgVal)
    end.

qname_to_internal_name(QName) ->
    case name_concat(QName) of
        Name when byte_size(Name) =< 255 ->
            {ok, erlang:binary_to_atom(Name)};
        Name ->
            {error, {too_long, Name}}
    end.

name_concat(#resource{virtual_host = <<"/">>, name = Name}) ->
    <<"%2F_", Name/binary>>;
name_concat(#resource{virtual_host = VHost, name = Name}) ->
    <<VHost/binary, "_", Name/binary>>.

check_auto_delete(Q) when ?amqqueue_is_auto_delete(Q) ->
    Name = amqqueue:get_name(Q),
    {protocol_error, precondition_failed, "invalid property 'auto-delete' for ~ts",
     [rabbit_misc:rs(Name)]};
check_auto_delete(_) ->
    ok.

check_exclusive(Q) when ?amqqueue_exclusive_owner_is(Q, none) ->
    ok;
check_exclusive(Q) when ?is_amqqueue(Q) ->
    Name = amqqueue:get_name(Q),
    {protocol_error, precondition_failed, "invalid property 'exclusive-owner' for ~ts",
     [rabbit_misc:rs(Name)]}.

check_non_durable(Q) when ?amqqueue_is_durable(Q) ->
    ok;
check_non_durable(Q) when not ?amqqueue_is_durable(Q) ->
    Name = amqqueue:get_name(Q),
    {protocol_error, precondition_failed, "invalid property 'non-durable' for ~ts",
     [rabbit_misc:rs(Name)]}.

run_checks([], _) ->
    ok;
run_checks([C | Checks], Q) ->
    case C(Q) of
        ok ->
            run_checks(Checks, Q);
        Err ->
            Err
    end.

-spec erpc_call(node(), module(), atom(), list(), non_neg_integer()) ->
    term() | {error, term()}.
erpc_call(Node, M, F, A, _Timeout)
  when Node =:= node()  ->
    %% Only timeout 'infinity' optimises the local call in OTP 23-25 avoiding a new process being spawned:
    %% https://github.com/erlang/otp/blob/47f121af8ee55a0dbe2a8c9ab85031ba052bad6b/lib/kernel/src/erpc.erl#L121
    try erpc:call(Node, M, F, A, infinity) of
        Result ->
            Result
    catch
        error:Err ->
            {error, Err}
    end;
erpc_call(Node, M, F, A, Timeout) ->
    case lists:member(Node, nodes()) of
        true ->
            try erpc:call(Node, M, F, A, Timeout) of
                Result ->
                    Result
            catch
                error:Err ->
                    {error, Err}
            end;
        false ->
            {error, noconnection}
    end.


-spec grow(atom(), node(), binary(), binary(), all | even, noop|voter|non_voter|promotable) ->
    [{rabbit_amqqueue:name(),
      {ok, pos_integer()} | {error, pos_integer(), term()}}].
grow(Type, Node, VhostSpec, QueueSpec, Strategy, Membership) ->
    Running = rabbit_nodes:list_running(),
    [begin
         Size = length(get_nodes(Q)),
         QName = amqqueue:get_name(Q),
         rabbit_log:info("~ts: adding a new member (replica) on node ~w",
                         [rabbit_misc:rs(QName), Node]),
         AddFun = add_fun(Q, Node, Membership),
         case AddFun() of
             ok ->
                 {QName, {ok, Size + 1}};
             {error, Err} ->
                 rabbit_log:warning(
                   "~ts: failed to add member (replica) on node ~w, error: ~w",
                   [rabbit_misc:rs(QName), Node, Err]),
                 {QName, {error, Size, Err}}
         end
     end
     || Q <- rabbit_amqqueue:list(),
        %% don't add a member if there is already one on the node
        amqqueue:get_type(Q) == Type,
        not lists:member(Node, get_nodes(Q)),
        %% node needs to be running
        lists:member(Node, Running),
        matches_strategy(Strategy, get_nodes(Q)),
        is_match(amqqueue:get_vhost(Q), VhostSpec) andalso
            is_match(get_resource_name(amqqueue:get_name(Q)), QueueSpec)].


add_fun(Q, Node, _) when ?amqqueue_is_stream(Q) ->
    fun() ->
            rabbit_stream_coordinator:add_replica(Q, Node)
    end;
add_fun(Q, Node, Membership) when ?amqqueue_is_quorum(Q) ->
    fun() ->
            rabbit_quorum_queue:add_member(Q, Node, Membership)
    end;
add_fun(Q, _Node, _) ->
    {error, io_lib:format("Unsupported queue type ~p",[amqqueue:get_type(Q)])}.

get_nodes(Q) ->
    #{nodes := Nodes} = amqqueue:get_type_state(Q),
    Nodes.

matches_strategy(all, _) -> true;
matches_strategy(even, Members) ->
    length(Members) rem 2 == 0.

is_match(Subj, E) ->
   nomatch /= re:run(Subj, E).

get_resource_name(#resource{name  = Name}) ->
    Name.
