#!/bin/bash

. $testbin/failover.defaults
. $testbin/test.h
. $testbin/common.h

testNo=0

for cnt in {1..4}; do

let testNo++
state=$(getNodesStatus | cut -f1 -d , | tr -d "[ , ><]" | tr '\n' '-' | sed s/-$//)
echoTab "Initial state"; echo $state 

case $state in
STANDBY-ACTIVE)
  #initial
  testId=switch$testNo
  failoverSwitch.sh -testId $testId -dsn1 repdb1_1121 -host1 ozone1 -host1mgm 192.168.141.138 -serverport1 53389 -dsn2 repdb2_1121 -host2 ozone2 -host2mgm 192.168.141.139 -serverport2 53385 -deleteTimesTenLog NO -updateTimesTenLog YES
  ;;
ACTIVE-STANDBY)
  #reversed
  testId=switch$testNo
  failoverSwitch.sh -testId $testId -testId switch$testNo -dsn2 repdb1_1121 -host2 ozone1 -host2mgm 192.168.141.138 -serverport2 53389 -dsn1 repdb2_1121 -host1 ozone2 -host1mgm 192.168.141.139 -serverport1 53385 -deleteTimesTenLog NO -updateTimesTenLog YES
  ;;
*)
  echo 'Error! Configuration not supported by this switch over script.'
  ;;
esac

  echo Summary | tee -a $testId.log
  echo --------------------- | tee -a $testId.log
  getTestSummary  | tee -a $testId.log
  listFailedSteps | tee -a $testId.log
  getTestEnvironment $user "$host1 $host2"

done

