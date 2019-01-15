#!/bin/bash

[ -z "$__included_librtti_sh" ] || return 0
declare -r __included_librtti_sh=1

# External tool dependencies, MUST always be defined,
# even if empty (e.g.: declare -a crt1_request_tools_list=())
declare -a crt1_request_tools_list=()

# Source startup code
. /netctl/lib/bash/crt1.sh

# Source functions libraries
. /netctl/lib/bash/libstring.sh

#
# RTTI
#

declare -ir \
	nctl_shell_type_alias=0 \
	nctl_shell_type_keyword=1 \
	nctl_shell_type_function=2 \
	nctl_shell_type_builtin=3 \
	nctl_shell_type_file=4 \
	nctl_shell_type_unknown=5

declare -ar nctl_shell_type=(
	[$nctl_shell_type_alias]='alias'
	[$nctl_shell_type_keyword]='keyword'
	[$nctl_shell_type_function]='function'
	[$nctl_shell_type_builtin]='builtin'
	[$nctl_shell_type_file]='file'
	[$nctl_shell_type_unknown]='unknown'
)

# Usage: nctl_shell_type_is <what>
nctl_shell_type_is()
{
	local what="${1:?missing 1st argument to function \"$FUNCNAME\" (what)}"
	local val
	local -i i

	if val="$(type -t "$what")"; then
		for ((i = ${#nctl_shell_type[@]}; --i >= 0;)) do
			[ "$val" = "${nctl_shell_type[$i]}" ] && return $i
		done
	fi

	return $nctl_shell_type_unknown
}
declare -fr nctl_shell_type_is

# Usage: nctl_is_alias <what>
nctl_is_alias()
{
	nctl_shell_type_is "$@"
	[ $? -eq $nctl_shell_type_alias ]
}
declare -fr nctl_is_alias

# Usage: nctl_is_keyword <what>
nctl_is_keyword()
{
	nctl_shell_type_is "$@"
	[ $? -eq $nctl_shell_type_keyword ]
}
declare -fr nctl_is_keyword

# Usage: nctl_is_function <what>
nctl_is_function()
{
	nctl_shell_type_is "$@"
	[ $? -eq $nctl_shell_type_function ]
}
declare -fr nctl_is_function

# Usage: nctl_is_builtin <what>
nctl_is_builtin()
{
	nctl_shell_type_is "$@"
	[ $? -eq $nctl_shell_type_builtin ]
}
declare -fr nctl_is_builtin

# Usage: nctl_is_file <what>
nctl_is_file()
{
	nctl_shell_type_is "$@"
	[ $? -eq $nctl_shell_type_file ]
}
declare -fr nctl_is_file

# Usage: nctl_arg_is_function <action> [<caller_name>]
nctl_arg_is_function()
{
	local action="${1:?missing 1st argument to function \"$FUNCNAME\" (action)}"

	nctl_is_function "$action" && return

	printf '%s: "%s" is not a function; Trace: %s\n' \
		"${2:-${FUNCNAME[1]:-$program_invocation_short_name}}" \
		"$action"
		"${FUNCNAME[*]}" >&2
	! :
}
declare -fr nctl_arg_is_function

# Usage: nctl_save_function_def <function_name> [<var>]
nctl_save_function_def()
{
	local nctl_save_function_def_f="${1:?missing 1st argument to function \"$FUNCNAME\" (function_name)}"
	local nctl_save_function_def_s
	local nctl_save_function_def_var="$2"

	# If no function defined: success
	nctl_save_function_def_s="$(declare -f "$nctl_save_function_def_f")" ||:

	nctl_return "$nctl_save_function_def_var" "$nctl_save_function_def_s"
}
declare -fr nctl_save_function_def

# Usage: nctl_restore_function_def <var_function_def>
nctl_restore_function_def()
{
	local nctl_restore_function_def_var="${1:?missing 1st argument to function \"$FUNCNAME\" (var_function_def)}"
	local nctl_restore_function_def_val

	nctl_get_val "$nctl_restore_function_def_var" nctl_restore_function_def_val || return

	eval "$nctl_restore_function_def_val"
}
declare -fr nctl_restore_function_def

# Usage: nctl_return [<var>] <val1> [<val2>...]
nctl_return()
{
	local -i nctl_return_rc=$?

	local nctl_return_var="$1"
	shift

	[ -n "$nctl_return_var" ] && nctl_is_valid_sh_var "$nctl_return_var" &&
		nctl_set_val "$nctl_return_var" "$@" ||
		printf '%s\n' "$@"

	return $nctl_return_rc
}
declare -fr nctl_return

# Usage: nctl_get_rc
nctl_get_rc()
{
	return ${PIPESTATUS[0]}
}
declare -fr nctl_get_rc

# Usage: nctl_set_rc <val>
nctl_set_rc()
{
	local -i rc=$1
	return $rc
}
declare -fr nctl_set_rc

# Usage: nctl_inc_rc <var>
nctl_inc_rc()
{
	nctl_get_rc
	local -i nctl_inc_rc_rc=$?

	local nctl_inc_rc_var="${1:?missing 1st argument to function \"$FUNCNAME\" (var)}"

	nctl_set_val \
		"$nctl_inc_rc_var" \
		$(($nctl_inc_rc_var + nctl_inc_rc_rc))

	return $nctl_inc_rc_rc
}
declare -fr nctl_inc_rc

# Usage: nctl_is_empty_var <var> [<index>]
nctl_is_empty_var()
{
	local var="${1:?missing 1st argument to function \"$FUNCNAME\" (var)}"
	local index="${2:-@}"
	local -i i

	eval "i=\"\${#$var[$index]}\""

	[ $i -eq 0 ]
}
declare -fr nctl_is_empty_var

# Usage: nctl_is_var_of_empty <var>
nctl_is_var_of_empty()
{
	local var="${1:?missing 1st argument to function \"$FUNCNAME\" (var)}"
	local s

	IFS='' eval "s=\"\${$var[*]}\""

	[ -z "$s" ]
}
declare -fr nctl_is_var_of_empty

# Usage: nctl_set_val <var> <val1> [<val2>] ...
nctl_set_val()
{
	local nctl_set_val_var="${1:?missing 1st argument to function \"$FUNCNAME\" (var)}"
	local nctl_set_val_s
	shift

	[ -n "${nctl_set_val_var##*\[*\]}" ] &&
		nctl_set_val_s='("$@")' ||
		nctl_set_val_s='"$*"'
	eval "$nctl_set_val_var=$nctl_set_val_s"
}
declare -fr nctl_set_val

# Usage: nctl_get_val_check_non_empty <var_get>
nctl_get_val_check_non_empty()
{
	! nctl_is_empty_var nctl_get_val_val
}
declare -fr nctl_get_val_check_non_empty

# Usage: __nctl_get_val_check <var_get>
# Scope: internal, local
# Context: nctl_get_val()
__nctl_get_val_check()
{
	nctl_get_val_check_non_empty "$@"
}
declare -fr __nctl_get_val_check

: ${nctl_get_val_check:='__nctl_get_val_check'}

# Usage: nctl_get_val <var_get> [<var>] [<index>]
nctl_get_val()
{
	local nctl_get_val_var_get="${1:?missing 1st argument to function \"$FUNCNAME\" (var_get)}"
	local nctl_get_val_var="$2"
	local nctl_get_val_index="${3:-@}"
	local -a nctl_get_val_val

	eval nctl_get_val_val="(\"\${$nctl_get_val_var_get[$nctl_get_val_index]}\")"

	! nctl_arg_is_function "$nctl_get_val_check" ||
		"$nctl_get_val_check" "$@"

	nctl_return "$nctl_get_val_var" "${nctl_get_val_val[@]}"
}
declare -fr nctl_get_val
