PROJECT = rabbitmq_ct_helpers
PROJECT_DESCRIPTION = Common Test helpers for RabbitMQ

DEPS = rabbit_common proper inet_tcp_proxy meck
TEST_DEPS = rabbit

XREF_IGNORE = [ \
    {'Elixir.OptionParser',split,1}, \
    {'Elixir.RabbitMQCtl',exec_command,2}]

dep_inet_tcp_proxy = git https://github.com/rabbitmq/inet_tcp_proxy master

# As this is a helper application we don't need other plugins.
DEP_PLUGINS = rabbit_common/mk/rabbitmq-build.mk

include ../../rabbitmq-components.mk
include ../../erlang.mk

ERLC_OPTS += +nowarn_export_all
