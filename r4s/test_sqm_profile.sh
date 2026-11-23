#!/bin/sh
# Test the actual prepared upstream script with mock tc/ip; no network changes.
set -e

SQM_LIB_DIR=$1
profile="$(dirname "$0")/packages/r4s-net-tune/files/usr/lib/sqm/r4s_cake_ingress.qos"

exercise() (
    IFACE=test-wan DEV=test-ifb UPLINK=10000 DOWNLINK=85000
    TC=record_tc IP=record_ip USE_MQ=$2
    ZERO_DSCP_INGRESS=1 OVERHEAD=42 STAB_MPU=84
    IQDISC_OPTS="dual-dsthost" EQDISC_OPTS="dual-srchost"
    sqm_debug() { :; }
    record_tc() { printf 'tc %s\n' "$*"; }
    record_ip() { printf 'ip %s\n' "$*"; }
    select_cake() {
        if [ "$USE_MQ" = 1 ]; then echo cake_mq; else echo cake; fi
    }
    get_stab_string() { :; }
    get_cake_lla_string() { echo "overhead $OVERHEAD mpu $STAB_MPU"; }

    # Upstream defaults.sh ends in a conditional; its shell code expects no -e.
    set +e
    . "$1"
    [ "${SUPPORT_MQ:-0}" -eq 1 ] || USE_MQ=0
    egress && ingress
)

stock=$(exercise "$SQM_LIB_DIR/piece_of_cake.qos" 0)
actual=$(exercise "$profile" 1)
test "$actual" = "$(printf '%s\n' "$stock" | sed '/^tc qdisc add dev test-ifb root /s/ besteffort / besteffort ingress /')"
printf '%s\n' "$actual" | grep -Fx 'tc qdisc add dev test-ifb root cake bandwidth 85000kbit overhead 42 mpu 84 diffserv3 nat besteffort ingress wash dual-dsthost'
printf '%s\n' "$actual" | grep -Fx 'tc qdisc add dev test-wan root cake bandwidth 10000kbit overhead 42 mpu 84 diffserv3 nat besteffort dual-srchost'
