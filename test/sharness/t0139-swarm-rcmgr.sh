#!/usr/bin/env bash
#
test_description="Test ipfs swarm ResourceMgr config and commands"

. lib/test-lib.sh

test_init_ipfs

# swarm limit|stats should fail in offline mode

test_expect_success 'disconnected: swarm limit requires running daemon' '
  test_expect_code 1 ipfs swarm limit system 2> actual &&
  test_should_contain "missing ResourceMgr" actual
'
test_expect_success 'disconnected: swarm stats requires running daemon' '
  test_expect_code 1 ipfs swarm stats all 2> actual &&
  test_should_contain "missing ResourceMgr" actual
'

# swarm limit|stats should succeed in online mode by default
# because Resource Manager is opt-out
test_launch_ipfs_daemon

# every scope has the same fields, so we only inspect System
test_expect_success 'ResourceMgr enabled: swarm limit' '
  ipfs swarm limit system --enc=json | tee json &&
  jq -e .Conns < json &&
  jq -e .ConnsInbound < json &&
  jq -e .ConnsOutbound < json &&
  jq -e .FD < json &&
  jq -e .Memory < json &&
  jq -e .Streams < json &&
  jq -e .StreamsInbound < json &&
  jq -e .StreamsOutbound < json
'

# every scope has the same fields, so we only inspect System
test_expect_success 'ResourceMgr enabled: swarm stats' '
  ipfs swarm stats all --enc=json | tee json &&
  jq -e .System.Memory < json &&
  jq -e .System.NumConnsInbound < json &&
  jq -e .System.NumConnsOutbound < json &&
  jq -e .System.NumFD < json &&
  jq -e .System.NumStreamsInbound < json &&
  jq -e .System.NumStreamsOutbound < json &&
  jq -e .Transient.Memory < json
'

# shut down the daemon, set a limit in the config, and verify that it's applied
test_kill_ipfs_daemon

test_expect_success "Set system conns limit while daemon is not running" "
  ipfs config --json Swarm.ResourceMgr.Limits.System.Conns 99999
"

test_expect_success "Set an invalid limit, which should result in a failure" "
  test_expect_code 1 ipfs config --json Swarm.ResourceMgr.Limits.System.Conns 'asdf' 2> actual &&
  test_should_contain 'failed to unmarshal' actual
"

test_launch_ipfs_daemon

test_expect_success 'Ensure the new system conns limit is applied' '
  ipfs swarm limit system --enc=json | tee json &&
  jq -e ".Conns == 99999" < json
'

test_expect_success 'Set system memory limit while the daemon is running' '
  ipfs swarm limit system | jq ".Memory = 99998" > system.json &&
  ipfs swarm limit system system.json
'

test_expect_success 'The new system limits were written to the config' '
  jq -e ".Swarm.ResourceMgr.Limits.System.Memory == 99998" < "$IPFS_PATH/config"
'

test_expect_success 'The new system limits are in the swarm limit output' '
  ipfs swarm limit system --enc=json | jq -e ".Memory == 99998"
'

# now test all the other scopes
test_expect_success 'Set limit on transient scope' '
  ipfs swarm limit transient | jq ".Memory = 88888" > transient.json &&
  ipfs swarm limit transient transient.json &&
  jq -e ".Swarm.ResourceMgr.Limits.Transient.Memory == 88888" < "$IPFS_PATH/config" &&
  ipfs swarm limit transient --enc=json | tee limits &&
  jq -e ".Memory == 88888" < limits
'

test_expect_success 'Set limit on service scope' '
  ipfs swarm limit svc:foo | jq ".Memory = 77777" > service-foo.json &&
  ipfs swarm limit svc:foo service-foo.json --enc=json &&
  jq -e ".Swarm.ResourceMgr.Limits.Service.foo.Memory == 77777" < "$IPFS_PATH/config" &&
  ipfs swarm limit svc:foo --enc=json | tee limits &&
  jq -e ".Memory == 77777" < limits
'

test_expect_success 'Set limit on protocol scope' '
  ipfs swarm limit proto:foo | jq ".Memory = 66666" > proto-foo.json &&
  ipfs swarm limit proto:foo proto-foo.json --enc=json &&
  jq -e ".Swarm.ResourceMgr.Limits.Protocol.foo.Memory == 66666" < "$IPFS_PATH/config" &&
  ipfs swarm limit proto:foo --enc=json | tee limits &&
  jq -e ".Memory == 66666" < limits
'

# any valid peer id
PEER_ID=QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN

test_expect_success 'Set limit on peer scope' '
  ipfs swarm limit peer:$PEER_ID | jq ".Memory = 66666" > peer-$PEER_ID.json &&
  ipfs swarm limit peer:$PEER_ID peer-$PEER_ID.json --enc=json &&
  jq -e ".Swarm.ResourceMgr.Limits.Peer.${PEER_ID}.Memory == 66666" < "$IPFS_PATH/config" &&
  ipfs swarm limit peer:$PEER_ID --enc=json | tee limits &&
  jq -e ".Memory == 66666" < limits
'

test_expect_success 'Get limit for peer scope with an invalid peer ID' '
  test_expect_code 1 ipfs swarm limit peer:foo 2> actual &&
  test_should_contain "invalid peer ID" actual
'

test_expect_success 'Set limit for peer scope with an invalid peer ID' '
  echo "{\"Memory\": 99}" > invalid-peer-id.json &&
  test_expect_code 1 ipfs swarm limit peer:foo invalid-peer-id.json 2> actual &&
  test_should_contain "invalid peer ID" actual
'

test_kill_ipfs_daemon

# test correct behavior when resource manager is disabled
test_expect_success 'Disable resource manager' '
  ipfs config --bool Swarm.ResourceMgr.Enabled false
'

test_launch_ipfs_daemon

test_expect_success 'Swarm limit should fail since RM is disabled' '
  test_expect_code 1 ipfs swarm limit system 2> actual &&
  test_should_contain "missing ResourceMgr" actual
'

test_expect_success 'Swarm stats should fail since RM is disabled' '
  test_expect_code 1 ipfs swarm stats all 2> actual &&
  test_should_contain "missing ResourceMgr" actual
'

test_kill_ipfs_daemon

test_done
