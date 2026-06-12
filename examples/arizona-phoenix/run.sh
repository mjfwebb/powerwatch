#!/usr/bin/env bash
# Run powerwatch with APS (Phoenix, Arizona) "Time-of-Use 4pm-7pm Weekdays"
# pricing. The rate schedule lives in aps-time-of-use.json next to this script;
# the jq program below picks the right rate for the current time, weekday and
# season. Any extra args (e.g. a refresh interval) are passed through.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

export POWERWATCH_LIVE=1
export POWERWATCH_CURR=USD
export POWERWATCH_PRICE_URL="file://$here/aps-time-of-use.json"
export POWERWATCH_PRICE_JQ='
  ($date | .[5:7]) as $m
  | (.summerMonths | index($m) != null) as $summer
  | (($dow | tonumber) <= 5) as $weekday
  | if   $weekday and $t >= .onPeak.from   and $t < .onPeak.to
    then (if $summer then .onPeak.summer else .onPeak.winter end)
    elif $weekday and ($summer | not) and $t >= .superOff.from and $t < .superOff.to
    then .superOff.winter
    else (if $summer then .offPeak.summer else .offPeak.winter end)
    end'

exec powerwatch "$@"
