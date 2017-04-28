-module(parameters_SUITE).

-compile(export_all).

-include_lib("eunit/include/eunit.hrl").
-include_lib("rabbit_common/include/rabbit_framing.hrl").

-define(EXCHANGE,    <<"test_exchange">>).
-define(TO_SHOVEL,   <<"to_the_shovel">>).
-define(FROM_SHOVEL, <<"from_the_shovel">>).
-define(UNSHOVELLED, <<"unshovelled">>).
-define(SHOVELLED,   <<"shovelled">>).
-define(TIMEOUT,     1000).

all() ->
    [
      {group, tests}
    ].

groups() ->
    [
      {tests, [parallel], [
          parse_amqp091,
          parse_amqp091_legacy,
          parse_amqp10,
          parse_amqp10_minimal,
          validate_amqp10
        ]}
    ].

%% -------------------------------------------------------------------
%% Testsuite setup/teardown.
%% -------------------------------------------------------------------

init_per_suite(Config) ->
    Config.

end_per_suite(Config) ->
    Config.

init_per_group(_, Config) ->
    Config.

end_per_group(_, Config) ->
    Config.

init_per_testcase(_Testcase, Config) -> Config.

end_per_testcase(_Testcase, Config) -> Config.


%% -------------------------------------------------------------------
%% Testcases.
%% -------------------------------------------------------------------

parse_amqp091_legacy(_Config) ->
    Params =
        [{<<"src-uri">>, <<"amqp://localhost:5672">>},
         {<<"src-protocol">>, <<"amqp091">>},
         {<<"dest-protocol">>, <<"amqp091">>},
         {<<"dest-uri">>, <<"amqp://remotehost:5672">>},
         {<<"add-forward-headers">>, true},
         {<<"add-timestamp-header">>, true},
         {<<"publish-properties">>, [{<<"cluster_id">>, <<"x">>},
                                     {<<"delivery_mode">>, 2}]},
         {<<"ack-mode">>, <<"on-publish">>},
         {<<"delete-after">>, <<"queue-length">>},
         {<<"prefetch-count">>, 30},
         {<<"reconnect-delay">>, 1001},
         {<<"src-queue">>, <<"a-src-queue">>},
         {<<"dest-queue">>, <<"a-dest-queue">>}
        ],

    test_parse_amqp091(Params).

parse_amqp091(_Config) ->
    Params =
        [{<<"src-uri">>, <<"amqp://localhost:5672">>},
         {<<"src-protocol">>, <<"amqp091">>},
         {<<"dest-protocol">>, <<"amqp091">>},
         {<<"dest-uri">>, <<"amqp://remotehost:5672">>},
         {<<"dest-add-forward-headers">>, true},
         {<<"dest-add-timestamp-header">>, true},
         {<<"dest-publish-properties">>, [{<<"cluster_id">>, <<"x">>},
                                          {<<"delivery_mode">>, 2}]},
         {<<"ack-mode">>, <<"on-publish">>},
         {<<"src-delete-after">>, <<"queue-length">>},
         {<<"src-prefetch-count">>, 30},
         {<<"reconnect-delay">>, 1001},
         {<<"src-queue">>, <<"a-src-queue">>},
         {<<"dest-queue">>, <<"a-dest-queue">>}
        ],
    test_parse_amqp091(Params).


test_parse_amqp091(Params) ->
    {ok, Result} = rabbit_shovel_parameters:parse({"vhost", "name"},
                                                  "my-cluster", Params),
    #{ack_mode := on_publish,
      name := "name",
      reconnect_delay := 1001,
      dest := #{module := rabbit_amqp091_shovel,
                uris := ["amqp://remotehost:5672"],
                props_fun := PropsFun
               },
      source := #{module := rabbit_amqp091_shovel,
                  uris := ["amqp://localhost:5672"],
                  prefetch_count := 30,
                  queue := <<"a-src-queue">>,
                  delete_after := 'queue-length'}
     } = Result,

    #'P_basic'{headers = HeadersResult,
               delivery_mode = 2,
               cluster_id = <<"x">>} = PBasic = PropsFun("amqp://localhost:5672",
                                                         "amqp://remotehost:5672",
                                                         #'P_basic'{headers = undefined}),
    ct:pal("PBasic ~p~n", [PBasic]),
    {_, array, [{table, Shovelled}]} = lists:keyfind(<<"x-shovelled">>, 1, HeadersResult),
    {_, long, _} = lists:keyfind(<<"x-shovelled-timestamp">>, 1, HeadersResult),

    ExpectedHeaders =
    [{<<"shovelled-by">>, "my-cluster"},
     {<<"shovel-type">>, <<"dynamic">>},
     {<<"shovel-name">>, "name"},
     {<<"shovel-vhost">>, "vhost"},
     {<<"src-uri">>,"amqp://localhost:5672"},
     {<<"dest-uri">>,"amqp://remotehost:5672"},
     {<<"src-queue">>,<<"a-src-queue">>},
     {<<"dest-queue">>,<<"a-dest-queue">>}],
    lists:foreach(fun({K, V}) ->
                          ?assertMatch({K, _, V},
                                       lists:keyfind(K, 1, Shovelled))
                  end, ExpectedHeaders),
    ok.

parse_amqp10(_Config) ->
    Params =
        [
         {<<"ack-mode">>, <<"on-publish">>},
         {<<"reconnect-delay">>, 1001},

         {<<"src-protocol">>, <<"amqp10">>},
         {<<"src-uri">>, <<"amqp://localhost:5672">>},
         {<<"src-address">>, <<"a-src-queue">>},
         {<<"src-delete-after">>, <<"never">>},
         {<<"src-prefetch-count">>, 30},

         {<<"dest-protocol">>, <<"amqp10">>},
         {<<"dest-uri">>, <<"amqp://remotehost:5672">>},
         {<<"dest-address">>, <<"a-dest-queue">>},
         {<<"dest-add-forward-headers">>, true},
         {<<"dest-add-timestamp-header">>, true},
         {<<"dest-application-properties">>, [{<<"some-app-prop">>,
                                               <<"app-prop-value">>}]},
         {<<"dest-message-annotations">>, [{<<"some-message-ann">>,
                                            <<"message-ann-value">>}]},
         {<<"dest-properties">>, [{<<"user_id">>, <<"some-user">>}]}
        ],

    ?assertMatch(
       {ok, #{name := "my_shovel",
              ack_mode := on_publish,
              source := #{module := rabbit_amqp10_shovel,
                          uris := ["amqp://localhost:5672"],
                          delete_after := never,
                          prefetch_count := 30,
                          source_address := <<"a-src-queue">>
                          },
              dest := #{module := rabbit_amqp10_shovel,
                        uris := ["amqp://remotehost:5672"],
                        target_address := <<"a-dest-queue">>,
                        message_annotations := #{<<"some-message-ann">> :=
                                                 <<"message-ann-value">>},
                        application_properties := #{<<"some-app-prop">> :=
                                                    <<"app-prop-value">>},
                        properties := #{user_id := <<"some-user">>},
                        add_timestamp_header := true,
                        add_forward_headers := true
                       }
             }},
        rabbit_shovel_parameters:parse({"vhost", "my_shovel"}, "my-cluster",
                                       Params)),
    ok.

parse_amqp10_minimal(_Config) ->
    Params =
        [
         {<<"src-protocol">>, <<"amqp10">>},
         {<<"src-uri">>, <<"amqp://localhost:5672">>},
         {<<"src-address">>, <<"a-src-queue">>},

         {<<"dest-protocol">>, <<"amqp10">>},
         {<<"dest-uri">>, <<"amqp://remotehost:5672">>},
         {<<"dest-address">>, <<"a-dest-queue">>}
        ],
    ?assertMatch(
       {ok, #{name := "my_shovel",
              ack_mode := on_confirm,
              source := #{module := rabbit_amqp10_shovel,
                          uris := ["amqp://localhost:5672"],
                          delete_after := never,
                          source_address := <<"a-src-queue">>
                          },
              dest := #{module := rabbit_amqp10_shovel,
                        uris := ["amqp://remotehost:5672"],
                        unacked := #{},
                        target_address := <<"a-dest-queue">>
                       }
             }},
        rabbit_shovel_parameters:parse({"vhost", "my_shovel"}, "my-cluster",
                                       Params)),
    ok.

validate_amqp10(_Config) ->
    Params =
        [
         {<<"ack-mode">>, <<"on-publish">>},
         {<<"reconnect-delay">>, 1001},

         {<<"src-protocol">>, <<"amqp10">>},
         {<<"src-uri">>, <<"amqp://localhost:5672">>},
         {<<"src-address">>, <<"a-src-queue">>},
         {<<"src-delete-after">>, <<"never">>},
         {<<"src-prefetch-count">>, 30},

         {<<"dest-protocol">>, <<"amqp10">>},
         {<<"dest-uri">>, <<"amqp://remotehost:5672">>},
         {<<"dest-address">>, <<"a-dest-queue">>},
         {<<"dest-add-forward-headers">>, true},
         {<<"dest-add-timestamp-header">>, true},
         {<<"dest-application-properties">>, [{<<"some-app-prop">>,
                                               <<"app-prop-value">>}]},
         {<<"dest-message-annotations">>, [{<<"some-message-ann">>,
                                               <<"message-ann-value">>}]},
         {<<"dest-properties">>, [{<<"user_id">>, <<"some-user">>}]}
        ],

        Res = rabbit_shovel_parameters:validate("my-vhost", <<"shovel">>,
                                                "my-shovel", Params, none),
        [] = validate_ok(Res),
        ok.

validate_ok([ok | T]) ->
    validate_ok(T);
validate_ok([[_|_] = L | T]) ->
    validate_ok(L) ++ validate_ok(T);
validate_ok([]) -> [];
validate_ok(X) ->
    exit({not_ok, X}).
