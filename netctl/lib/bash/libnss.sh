#!/bin/bash

[ -z "$__included_libnss_sh" ] || return 0
declare -r __included_libnss_sh=1

# External tool dependencies, MUST always be defined,
# even if empty (e.g.: declare -a crt1_request_tools_list=())
declare -a crt1_request_tools_list=(
	'getent'		# getent(1)
)

# Source startup code
. @dest@/netctl/lib/bash/crt1.sh

# Source functions libraries
. @dest@/netctl/lib/bash/librtti.sh

# Usage: nctl_check_nss_entry <entry> <db> [<var>]
nctl_check_nss_entry()
{
	local ncne_entry="${1:?missing 1st argument to function \"$FUNCNAME\" (entry)}"
	local ncne_db="${2:?missing 2d argument to function \"$FUNCNAME\" (db)}"
	local ncne_var="$3"

	getent "$ncne_db" "$ncne_entry" &>/dev/null

	nctl_return "$ncne_var" "$ncne_entry"
}
declare -fr nctl_check_nss_entry
