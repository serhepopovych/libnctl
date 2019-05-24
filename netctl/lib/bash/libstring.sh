#!/bin/bash

[ -z "$__included_libstring_sh" ] || return 0
declare -r __included_libstring_sh=1

# External tool dependencies, MUST always be defined,
# even if empty (e.g.: declare -a crt1_request_tools_list=())
declare -a crt1_request_tools_list=()

# Source startup code
. @target@/netctl/lib/bash/crt1.sh

# Source functions libraries
. @target@/netctl/lib/bash/librtti.sh

#
# Basic char/string operations
#

# Usage: __nctl_casemod_40 <string|char> <op> [<var>]
# Requires: bash >= 4.x
__nctl_casemod_40()
{
	local __ncm40_s="${1:?missing 1st argument to function \"$FUNCNAME\" (string|char)}"
	local __ncm40_op="${2:?missing 2d argument to function \"$FUNCNAME\" (op)}"
	local __ncm40_var="$3"
	local -i __ncm40_rc

	{
		trap ':' ERR
		eval __ncm40_s="\${__ncm40_s$__ncm40_op}"
		rc=$?
		trap - ERR
	} 2>/dev/null

	nctl_return "$__ncm40_var" "$__ncm40_s"

	return $__ncm40_rc
}
declare -fr __nctl_casemod_40

# Usage: nctl_tolower <single_char> [<var>]
# Result: if <single_char> is in [A-Z] class: return [a-z] equivalent
#         else return unmodified <single_char>
nctl_tolower()
{
	[ ${#1} -eq 1 ] || return 3

	local ntl_s="${1:?missing 1st argument to function \"$FUNCNAME\" (single_char)}"
	local ntl_var="$2"

	if ! __nctl_casemod_40 "$ntl_s" ',' 'ntl_s'; then
		if [ -z "${ntl_s##[[:upper:]]}" ]; then
			printf -v ntl_s '%u' \'"$ntl_s"
			printf -v ntl_s '%x' $((ntl_s + 32))
			printf -v ntl_s "\x$ntl_s"
		fi
	fi

	[ "$ntl_s" != "$1" ]

	nctl_return "$ntl_var" "$ntl_s"
}
declare -fr nctl_tolower

# Usage: nctl_toupper <single_char> [<var>]
# Result: if <single_char> is in [a-z] class: return [A-Z] equivalent
#         else return unmodified <single_char>
nctl_toupper()
{
	[ ${#1} -eq 1 ] || return 3

	local ntu_s="${1:?missing 1st argument to function \"$FUNCNAME\" (single_char)}"
	local ntu_var="$2"

	if ! __nctl_casemod_40 "$ntu_s" '^' 'ntu_s'; then
		if [ -z "${ntu_s##[[:lower:]]}" ]; then
			printf -v ntu_s '%u' \'"$ntu_s"
			printf -v ntu_s '%x' $((ntu_s - 32))
			printf -v ntu_s "\x$ntu_s"
		fi
	fi

	[ "$ntu_s" != "$1" ]

	nctl_return "$ntu_var" "$ntu_s"
}
declare -fr nctl_toupper

# Usage: nctl_strtolower <string_of_char> [<var>]
# Result: lowercased string by applying tolower() to each char in
#         <string_of_char>
nctl_strtolower()
{
	local nstl_s="${1:?missing 1st argument to function \"$FUNCNAME\" (string_of_char)}"
	local nstl_var="$2"
	local nstl_i nstl_c

	if ! __nctl_casemod_40 "$nstl_s" ',,' 'nstl_s'; then
		nstl_s=
		for ((nstl_i = ${#1}; --nstl_i >= 0;)); do
			nctl_tolower "${1:$nstl_i:1}" c
			nstl_s="$nstl_c$nstl_s"
		done
	fi

	[ "$nstl_s" != "$1" ]

	nctl_return "$nstl_var" "$nstl_s"
}
declare -fr nctl_strtolower

# Usage: nctl_strtoupper <string_of_char> [<var>]
# Result: uppercased string by applying toupper() to each char in
#         <string_of_char>
nctl_strtoupper()
{
	local nstu_s="${1:?missing 1st argument to function \"$FUNCNAME\" (string_of_char)}"
	local nstu_var="$2"
	local nstu_i nstu_c

	if ! __nctl_casemod_40 "$nstu_s" '^^' 'nstu_s'; then
		nstu_s=
		for ((nstu_i = ${#1}; --nstu_i >= 0;)); do
			nctl_toupper "${1:$nstu_i:1}" nstu_c
			nstu_s="$nstu_c$nstu_s"
		done
	fi

	[ "$nstu_s" != "$1" ]

	nctl_return "$nstu_var" "$nstu_s"
}
declare -fr nctl_strtoupper

# Usage: nctl_is_valid_sh_var <string>
nctl_is_valid_sh_var()
{
	local s="${1:?missing 1st argument to function \"$FUNCNAME\" (string)}"

	[ -n "${s##*[^[:alnum:]_]*}" ] && ! [ "${s:0:1}" -ge 0 ] 2>/dev/null
}
declare -fr nctl_is_valid_sh_var

# Usage: nctl_str2sh_var <string> [<var>]
# Result: make variable name from 'string' by replacing all non
#         bash var name characters with '_' and making var to
#         begin with '_' if it first char is digit.
nctl_str2sh_var()
{
	local nssv_s="${1:?missing 1st argument to function \"$FUNCNAME\" (string)}"
	local nssv_var="$2"

	nssv_s="${nssv_s//[^[:alnum:]_]/_}"
	[ "${nssv_s:0:1}" -ge 0 ] 2>/dev/null && nssv_s="_$nssv_s" ||:

	nctl_return "$nssv_var" "$nssv_s"
}
declare -fr nctl_str2sh_var

# Usage: nctl_strreplace <val> <pattern1> [<pattern2>] [<var>]
# Example: nctl_strreplace 'str1 fail str2 fail' '/*([[:space:]])fail*([[:space:]])' ' ok '
nctl_strreplace()
{
	local nsr_s="${1:?missing 1st argument to function \"$FUNCNAME\" (val)}"
	local nsr_p1="${2:?missing 1st argument to function \"$FUNCNAME\" (pattern1)}"
	local nsr_p2="$3"
	local nsr_var="$4"

	local __nsr_shopt="$(shopt -p extglob)"
	shopt -s extglob

	eval "nsr_s=\${nsr_s/$nsr_p1/$nsr_p2}"

	eval "$__nsr_shopt"

	nctl_return "$nsr_var" "$nsr_s"
}
declare -fr nctl_strreplace

# Usage: nctl_skip_spaces <string> [<var>]
# Result: removed extra spaces from begin/end of <string>,
#         multiple spaces are replaced with single one.
nctl_skip_spaces()
{
	local nss_s="${1:?missing 1st argument to function \"$FUNCNAME\" (string)}"
	local nss_var="$2"

	nctl_strreplace "$nss_s" '/+([[:space:]])' ' ' nss_s
	nss_s="${nss_s##[[:space:]]}"
	nss_s="${nss_s%%[[:space:]]}"

	nctl_return "$nss_var" "$nss_s"
}
declare -fr nctl_skip_spaces

# Usage: nctl_strset <length> <char> [<var>]
# Result: string, of length <length>, filled with <char>
nctl_strset()
{
	local -i ns_length="${1:?missing 1st argument to function \"$FUNCNAME\" (length)}"
	local ns_char="${2:?missing 2d argument to function \"$FUNCNAME\" (char)}"
	local ns_s
	local ns_var="$3"

	ns_char="${ns_char:0:1}"
	for ((; --ns_length >= 0;)); do
		ns_s="$ns_s$ns_char"
	done

	nctl_return "$ns_var" "$ns_s"
}
declare -fr nctl_strset

# Usage: __nctl_is_empty <string> [<var>]
__nctl_is_empty()
{
	local __nie_s="$1"
	local __nie_var="$2"

	if [ -n "$__nie_s" ]; then
		# nctl_skip_spaces() very slow here: do manually
		__nie_s="${__nie_s##[[:space:]]}"
		__nie_s="${__nie_s%%[[:space:]]}"

		[ -z "$__nie_s" ]
	fi

	nctl_return "$__nie_var" "$__nie_s"
}
declare -fr __nctl_is_empty

# Usage: nctl_is_empty <string>
nctl_is_empty()
{
	local nie_s="$1"

	__nctl_is_empty "$nie_s" nie_s
}
declare -fr nctl_is_empty

# One line comments may start with one of these chars
: ${NCTL_COMMENT_CHARS:='#'}

# Usage: nctl_is_comment <string>
nctl_is_comment()
{
	local nic_s="$1"

	__nctl_is_empty "$nic_s" nic_s ||
		[ -z "${NCTL_COMMENT_CHARS##*${s:0:1}*}" ]
}
declare -fr nctl_is_comment

# Usage: nctl_skip_comments <string> [<var>]
nctl_skip_comments()
{
	local nsc_s="$1"
	local nsc_var="$2"

	__nctl_is_empty "$nsc_s" nsc_s && return

	local __nsc_shopt="$(shopt -p extglob)"
	shopt -s extglob

	nsc_s="${1%%*([[:space:]])#*}"

	eval "$__nsc_shopt"

	[ -z "$nsc_s" ]

	nctl_return "$nsc_var" "$nsc_s"
}
declare -fr nctl_skip_comments

# Usage: nctl_fs_path_clean <dir> [<var>]
# Example: nctl_fs_path_clean /var/run////bird///
#          /var/run/bird
nctl_fs_path_clean()
{
	local nfpc_s="${1:?missing 1st argument to function \"$FUNCNAME\" (dir)}"
	local nfpc_var="$2"

	nctl_strreplace "$nfpc_s" '/+(\/)' '/' nfpc_s
	nfpc_s="${nfpc_s%/}"
	nfpc_s="${nfpc_s:-/}"

	nctl_return "$nfpc_var" "$nfpc_s"
}
declare -fr nctl_fs_path_clean

# Usage: nctl_top_dir_name <dir> [<var>]
# Example: nctl_top_dir_name /var/run/bird/bird.ctl
#          /var/run/bird
nctl_top_dir_name()
{
	local ntdn_s="${1:?missing 1st argument to function \"$FUNCNAME\" (dir)}"
	local ntdn_var="$2"

	nctl_strreplace "$ntdn_s" '/+(\/)' '/' ntdn_s
	ntdn_s="${ntdn_s%/*}"
	ntdn_s="${ntdn_s:-/}"

	nctl_return "$ntdn_var" "$ntdn_s"
}
declare -fr nctl_top_dir_name

# Usage: nctl_strsep <string> <separators> [<var>]
nctl_strsep()
{
	local nss_string="${1:?missing 1st argument to \"$FUNCNAME\" (string)}"
	local nss_separators="${2:?missing 2d argument to function \"$FUNCNAME\" (separators)}"
	local nss_var="$3"
	local -a nss_a
	local nss_eval

	nctl_strreplace "$nss_string" "/[$nss_separators]" $'\n' nss_a

	nss_eval="$IFS"
	IFS=$'\n'
	nctl_set_val nss_a $nss_a
	IFS="$nss_eval"

	nctl_return "$nss_var" "${nss_a[@]}"
}
declare -fr nctl_strsep

# Usage: nctl_templ_expand <var> <fmt> [<file1> <file2> ...]
nctl_templ_expand()
{
	local nte_var="${1:?missing 1st argument to \"$FUNCNAME\" (var)}"
	local nte_fmt="${2:?missing 1st argument to \"$FUNCNAME\" (fmt)}"
	shift 2
	local nte_eval
	local -i nte_rc=0

	nte_eval="$IFS"
	IFS=$'\n'
	nctl_set_val "$nte_var" $(printf "$nte_fmt\n" "$@") ||
		nctl_inc_rc nte_rc
	IFS="$nte_eval"

	return $nte_rc
}
declare -fr nctl_templ_expand

# Usage: nctl_paths_expand_s <file1_pattern> [<file2_pattern> ...]
nctl_paths_expand_s()
{
	npes__nctl_paths_expanded_out()
	{
		printf '%s\n' "$@"
		: $((lines+=$#))
	}
	local __shopt=`shopt -p nullglob`
	shopt -s nullglob

	local f
	local -i lines=0
	for f in "$@"; do
		eval "npes__nctl_paths_expanded_out $f"
	done

	eval "$__shopt"

	# Remove internal function(s) from global namespace
	unset -f npes__nctl_paths_expanded_out

	[ $lines -gt 0 ]
}
declare -fr nctl_paths_expand_s

# Usage: nctl_paths_expand_a <var> <file1_pattern> [<file2_pattern> ...]
nctl_paths_expand_a()
{
	local npea_var="${1:?missing 1st argument to \"$FUNCNAME\" (var)}"
	shift
	local npea_eval
	local -i npea_rc=0

	npea_eval="$IFS"
	IFS=$'\n'
	nctl_set_val "$npea_var" $(nctl_paths_expand_s "$@") ||
		nctl_inc_rc npea_rc
	IFS="$npea_eval"

	return $npea_rc
}
declare -fr nctl_paths_expand_a

# Usage: nctl_args2pat <var> [<sep>] <val1>...
nctl_args2pat()
{
	local nap_var="${1:?missing 1st argument to \"$FUNCNAME\" (var)}"
	local nap_sep="${2:-|}"
	shift 2
	local nap_pat

	nap_pat="$nap_sep"
	while [ $# -gt 0 ]; do
		[ -z "${nap_pat##*$nap_sep$1$nap_sep*}" ] ||
			nap_pat="$nap_pat$1$nap_sep"
		shift
	done

	nctl_set_val "$nap_var" "$nap_pat"
}
declare -fr nctl_args2pat

# Usage: nctl_mtch4pat <var> [<sep>] <pat> <str1>...
nctl_mtch4pat()
{
	local nmp_var="$1"
	local nmp_sep="${2:-|}"
	local nmp_pat="${3:?missing 3rd argument to \"$FUNCNAME\" (pat)}"
	shift 3
	local nmp_mtch="$nmp_sep"
	local -a nmp_items=()
	local -i nmp_i=0
	local -i nmp_rc=0

	while [ $# -gt 0 ]; do
		if [ -z "${nmp_pat##*$nmp_sep$1$nmp_sep*}" ]; then
			[ -n "${nmp_mtch##*$nmp_sep$1$nmp_sep*}" ] ||
				continue
			nmp_mtch="$nmp_mtch$1$nmp_sep"
			nmp_items[$((nmp_i++))]="$1"
		else
			nmp_rc=1
			[ -n "$nmp_var" ] || break
		fi
		shift
	done

	[ $nmp_rc -eq 0 ]

	nctl_return "$nmp_var" "${nmp_items[@]}"
}
declare -fr nctl_mtch4pat
