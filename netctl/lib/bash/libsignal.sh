#!/bin/bash

[ -z "$__included_libsignal_sh" ] || return 0
declare -r __included_libsignal_sh=1

# External tool dependencies, MUST always be defined,
# even if empty (e.g.: declare -a crt1_request_tools_list=())
declare -a crt1_request_tools_list=()

# Source startup code
. @target@/netctl/lib/bash/crt1.sh

# Source functions library
. @target@/netctl/lib/bash/librtti.sh

# Usage: nctl_trap <new_sighandler> <old_sigspec_var> sigspec1 [sigspec2...]
nctl_trap()
{
	local nctl_trap_new_sighandler="${1:?missing 1st argument to function \"$FUNCNAME\" (new_sighandler)}"
	local nctl_trap_old_sigspec_var="${2:?missing 2d argumnent to function \"$FUNCNAME\" (old_sigspec_var)}"
	shift 2
	local -a nctl_trap_old_sigspec
	local -i nctl_trap_i nctl_trap_n=$#
	local nctl_trap_sigspec nctl_trap_sighandler

	for ((nctl_trap_i = 0; nctl_trap_i < nctl_trap_n; nctl_trap_i++)); do
		nctl_trap_sigspec="$1"
		shift
		# Skip empty sigspec entries
		[ -n "$nctl_trap_sigspec" ] || continue

		# Save current trap handler (doesn't work for DEBUG, ERR and RETURN)
		if ! nctl_trap_sighandler="$(trap -p "$nctl_trap_sigspec" 2>/dev/null)"; then
			printf '%s: invalid signal specification "%s"\n' \
				"$FUNCNAME" "$nctl_trap_sigspec" >&2
			nctl_untrap nctl_trap_old_sigspec
			return 3
		fi
		nctl_trap_old_sigspec[$nctl_trap_i]="${nctl_trap_sighandler:-trap -- '-' $nctl_trap_sigspec}"

		# Install new signal handler
		trap -- "$nctl_trap_new_sighandler" "$nctl_trap_sigspec"
	done

	nctl_set_val "$nctl_trap_old_sigspec_var" "${nctl_trap_old_sigspec[@]}"
}
declare -fr nctl_trap

# Usage: nctl_untrap <old_sigspec_var>
nctl_untrap()
{
	local old_sigspec_var="${1:?missing 1st argumnent to function \"$FUNCNAME\" (old_sigspec_var)}"
	local -a old_sigspec new_sigspec
	local -i i n
	local sigspec sighandler new_sighandler

	nctl_get_val "$old_sigspec_var" old_sigspec || return

	for ((i = 0, n=${#old_sigspec[@]}; i < n; i++)); do
		sighandler="${old_sigspec[$i]}"

		# Skip empty sigspec entries
		[ -n "$sighandler" ] || continue

		# Save current trap handler (doesn't work for DEBUG, ERR and RETURN)
		#
		# Ignore unsupported pseudo signals: these signals MUST be handled
		# directly because untrapping of these are significat only for calling
		# function (nctl_untrap() unset its own, local copy instead of global).
		sigspec="${sighandler##*[[:space:]]}"
		case "$sigspec" in
			DEBUG|ERR|RETURN)
				continue
				;;
		esac
		if ! new_sighandler="$(trap -p "$sigspec" 2>/dev/null)"; then
			printf '%s: invalid signal specification "%s"\n' \
				"$FUNCNAME" "$sigspec">&2
			"$FUNCNAME" new_sigspec
			return 3
		fi
		new_sigspec[$i]="${new_sighandler:-trap -- '-' $sigspec}"

		# Reset signal handler to its origin
		eval "$sighandler"
	done
}
declare -fr nctl_untrap
