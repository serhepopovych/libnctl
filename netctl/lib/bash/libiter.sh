#!/bin/bash

[ -z "$__included_libiter_sh" ] || return 0
declare -r __included_libiter_sh=1

# External tool dependencies, MUST always be defined,
# even if empty (e.g.: declare -a crt1_request_tools_list=())
declare -a crt1_request_tools_list=()

# Source startup code
. @dest@/netctl/lib/bash/crt1.sh

# Source functions libraries
. @dest@/netctl/lib/bash/librtti.sh

# Usage: __nctl_action_for_each_pre <action> <item1> [<item2>...]
# Scope: local, internal
# Context: nctl_action_for_each()
__nctl_action_for_each_pre()
{
	return 0
}
declare -fr __nctl_action_for_each_pre

# Call default (inherit)
: ${nctl_action_for_each_pre:='__nctl_action_for_each_pre'}

# Usage: __nctl_action_for_each_post <action> <item1> [<item2>...]
# Scope: local, internal
# Context: nctl_action_for_each()
__nctl_action_for_each_post()
{
	return 0
}
declare -fr __nctl_action_for_each_post

# Call default (inherit)
: ${nctl_action_for_each_post:='__nctl_action_for_each_post'}

# Usage: nctl_action_for_each <action> <item1> [<item2>...]
nctl_action_for_each()
{
	local action="${1:?missing 1st argument to function \"$FUNCNAME\" (action)}"
	shift

	[ $# -le 0 ] && return

	nctl_arg_is_function "$action" || return
	nctl_arg_is_function "$nctl_action_for_each_pre" || return
	nctl_arg_is_function "$nctl_action_for_each_post" || return

	local -i rc=0
	local iter

	# pre
	"$nctl_action_for_each_pre" "$@" || nctl_inc_rc rc

	# action
	for iter in "$@"; do
		"$action" "$iter" || nctl_inc_rc rc
	done

	# post
	"$nctl_action_for_each_post" "$@" || nctl_inc_rc rc

	return $rc
}
declare -fr nctl_action_for_each

# Usage: nctl_action_for_each_with_set_globs <iterator> <entry1> <entry2> ...
nctl_action_for_each_with_set_globs()
{
	local -i rc=0
	local __shopt

	__shopt="$(shopt -p extglob nullglob dotglob)"
	shopt -s extglob nullglob dotglob

	nctl_action_for_each "$@" || nctl_inc_rc rc

	eval "$__shopt"

	return $rc
}
declare -fr nctl_action_for_each_with_set_globs
