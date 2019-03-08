#!/bin/bash

[ -z "$__included_libinet_sh" ] || return 0
declare -r __included_libinet_sh=1

# External tool dependencies, MUST always be defined,
# even if empty (e.g.: declare -a crt1_request_tools_list=())
declare -a crt1_request_tools_list=()

# Source startup code
. @target@/netctl/lib/bash/crt1.sh

# Source functions libraries
. @target@/netctl/lib/bash/libbool.sh

#
# MAC address manipulation routines
#

# Usage: nctl_is_valid_mac <mac_address>
nctl_is_valid_mac()
{
	local addr="${1:?missing 1st argument to function \"$FUNCNAME\" (mac_address)}"
	local -i val
	local -ir MAC_MAX_BYTES=$((48/8))

	addr="${addr//[[:space:]]/}"
	[ "$addr" = "$1" ] || return

	set -- ${addr//:/ : }

	# XX:XX:XX:XX:XX:XX
	#  XX - 6
	#   : - 5
	[ $# -eq $((MAC_MAX_BYTES + 5)) ] || return

	while :; do
		# XX
		eval val="16#$1" &>/dev/null || return
		[ $val -ge 0 -a $val -le 255 ] || return
		shift

		[ $# -gt 0 ] || break

		# :
		[ "$1" = ':' ] || return
		shift
	done
}
declare -fr nctl_is_valid_mac

#
# IPv4/IPv6 address manipluation routines
#

# Usage: nctl_is_valid_ipv4 <ipv4_address>
nctl_is_valid_ipv4()
{
	local addr="${1:?missing 1st argument to function \"$FUNCNAME\" (ipv4_address)}"
	local b bytes=0
	local -i val
	local -ir IPV4_MAX_BYTES=$((32/8))

	while [ -n "$addr" ]; do
		# Get byte
		b="${addr%%.*}"
		if [ -z "$b" ]; then
			# Cut . from first byte
			addr="${addr#.}"
			[ -n "$addr" -a "${addr:0:1}" != '.' -a $bytes -gt 0 ] || return
			continue
		fi
		# Check byte value
		eval val="10#$b" &>/dev/null || return
		[ $val -ge 0 -a $val -le 255 ] || return
		# Count number of bytes and check overflow
		[ $((++bytes)) -le $IPV4_MAX_BYTES ] || return
		# Cut leftmost byte
		addr="${addr#$b}"
	done
	[ $bytes -eq $IPV4_MAX_BYTES ]
}
declare -fr nctl_is_valid_ipv4

# Usage: nctl_is_valid_ipv6 <ipv6_address>
nctl_is_valid_ipv6()
{
	local addr="${1:?missing 1st argument to function \"$FUNCNAME\" (ipv6_address)}"
	local w shortcut=n words=0
	local -i val
	local -ir IPV6_MAX_WORDS=$((128/16))

	while [ -n "$addr" ]; do
		# Get word
		w="${addr%%:*}"
		if [ -z "$w" ]; then
			# Is this shortcut ::?
			if [ "${addr:1:1}" = ':' ]; then
				! nctl_is_yes "$shortcut" || return
				shortcut=y
				addr="${addr#::}"
				# Is next char :?
				[ "${addr:0:1}" != ':' ] || return
			else
				# Cut : from last word
				addr="${addr#:}"
				[ -n "$addr" -a $words -gt 0 ] || return
			fi
			continue
		fi
		# Check word value
		eval val="16#$w" &>/dev/null || return
		[ $val -ge 0 -a $val -le 65535 ] || return
		# Count number of words and check overflow
		[ $((++words)) -le $IPV6_MAX_WORDS ] || return
		# Cut leftmost word
		addr="${addr#$w}"
	done
	if nctl_is_yes "$shortcut"; then
		[ $words -lt "$IPV6_MAX_WORDS" ]
	else
		[ $words -eq "$IPV6_MAX_WORDS" ]
	fi
}
declare -fr nctl_is_valid_ipv6

# Usage: nctl_is_valid_ip_address <ipv4|ipv6>
nctl_is_valid_ip_address()
{
	local ip="${1:?missing 1st argument to function \"$FUNCNAME\" (ip)}"
	nctl_is_valid_ipv4 "$ip" || nctl_is_valid_ipv6 "$ip"
}
declare -fr nctl_is_valid_ip_address

# Usage: nctl_is_valid_port <port>
nctl_is_valid_port()
{
	local port="${1:?missinsg 1st argument to function \"$FUNCNAME\"}"

	[ "$port" -ge 0 -a "$port" -le 65535 ] 2>/dev/null
}
declare -fr nctl_is_valid_port

