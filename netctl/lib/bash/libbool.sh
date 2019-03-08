#!/bin/bash

[ -z "$__included_libbool_sh" ] || return 0
declare -r __included_libbool_sh=1

# External tool dependencies, MUST always be defined,
# even if empty (e.g.: declare -a crt1_request_tools_list=())
declare -a crt1_request_tools_list=()

# Source startup code
. @target@/netctl/lib/bash/crt1.sh

# Usage: nctl_is_yes <value>
# Result: return 0 if value is one of (case insensitive): yes, on, true, 1
nctl_is_yes()
{
	case "$1" in
		[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|[Oo][Nn]|[Yy]|1)
			:
			;;
		*)
			! :
			;;
	esac
}
declare -fr nctl_is_yes

# Usage: nctl_is_no <value>
# Result: return 0 if value is one of (case insensitive): no, off, false, 0
nctl_is_no()
{
	case "$1" in
		[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]|[Oo][Ff][Ff]|[Nn]|0)
			:
			;;
		*)
			! :
			;;
	esac
}
declare -fr nctl_is_no
