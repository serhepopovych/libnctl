#!/bin/bash

if [ -n "$__included_crt1_sh" ]; then
	## Load calling script configuration file
	crt1_source_cfg "${BASH_SOURCE[1]}"

	## Ensure tools on which calling script depends found in system
	crt1_request_tools "${crt1_request_tools_list[@]}"

	return 0
fi
declare -r __included_crt1_sh=1

### Helper function(s) for debugging purposes

# Usage: crt1_backtrace [<var>]
crt1_backtrace()
{
	local cb_var="$1"
	local -a cb_buf
	local -i cb_i cb_size

	for ((cb_i = 0, cb_size=${#FUNCNAME[@]};
		cb_i < cb_size; cb_i++)); do
		printf -v cb_buf[$cb_i] \
			'  %s: %s: %d\n' \
			"${FUNCNAME[$cb_i]}" \
			"${BASH_SOURCE[$((cb_i + 1))]:-${BASH_SOURCE[1]}}" \
			"${BASH_LINENO[$cb_i]}"
	done

	IFS='' eval "
		printf ${cb_var:+-v \"$cb_var\"} \
			'\nFunction call stack backtrace (func: file: line):\n%s\n' \
			\"\${cb_buf[*]}\"
		"
}
declare -fr crt1_backtrace

# Usage: crt1_fatal [<rc>] <fmt> [<arg1> <arg2>...]
crt1_fatal()
{
	local -i rc="${1:-${nctl_rc:-2}}"
	local fmt="${2:?missing 2d argument to function \"$FUNCNAME\" (fmt)}"
	shift 2
	local buf

	crt1_backtrace buf
	printf "*** FATAL ***\n\n$fmt\n" "$@" >&2
	printf '%s\n' "$buf" >&2

	if [ "$rc" -eq 0 ]; then
		[ $nctl_rc -ne 0 ] && rc=$nctl_rc || rc=2
	fi

	# Exit unconditionally with error status
	exit $rc
}
declare -fr crt1_fatal

### Library specific configuration

# Each library has a set of internal/public variables that might be
# adjusted by library specific config file stored in '.cfg' directory
# in the library directory.

# Usage: crt1_source_cfg <libargv0>
crt1_source_cfg()
{
	local libargv0="${1:?missing 1st argument to function \"$FUNCNAME\" (libargv0)}"
	local libpath
	local libname
	local libcfg

	# {libpath}/.cfg
	libpath="${libargv0%/*\.sh}"
	[ "$libpath" != "$libargv0 " -a \
	  -d "$libpath" ] || return 0
	libpath="$libpath/.cfg"
	[ -d "$libpath" ] || return 0

	# {libname}.cfg
	libname="${libargv0##*/}"
	libname="${libname/%\.sh/.cfg}"

	# {libpath}/.cfg/{libname}.cfg
	libcfg="$libpath/$libname"

	# Source specific library configuration if not empty
	[ -f "$libcfg" -a -s "$libcfg" ] && . "$libcfg" ||:
}
declare -fr crt1_source_cfg

### Check availability of external tools

# Nearly any script depends on external executables
# installed in system to perform specific task
#
# Even most of the generic code of this library and
# scripts that use it MUST be written in pure bash(1)
# language, there are specific tasks that might be
# performed by external tool only (e.g.: configuration
# of in-kernel firewall rules with ipset/iptables rules).
#
# Howerver it is common, that required tool is not
# installed in system and thus script can't perform
# it's task without it.
#
# This simple approach created to help users to resolve
# script dependencies on external tools before using
# script functionality.

# Usage: crt1_request_tools <tool1>...
crt1_request_tools()
{
	local tool
	local var

	# crt1_request_tools_list variable MUST always be defined, even
	# if it is empty
	if ! declare -p crt1_request_tools_list &>/dev/null; then
		crt1_fatal '' \
'crt1_request_tools_list variable must be defined in every script
sourcing crt1.sh.

Make sure you declare this variable before sourcing crt1.sh
startup code in "%s" script.' \
		"${BASH_SOURCE[2]}"
	fi

	for tool in "$@"; do
		[ -n "$tool" ] || continue

		# Try to find tool
		{
			hash -t "$tool" || hash "$tool"
		} &>/dev/null && continue

		# Notify about missing tool
		crt1_fatal '' \
'Could not statisfy dependency on external executable
file "%s": not found in directories in PATH environment
variable.

Try to install package that provides "%s" using package
management system of your distribution (e.g. aptitude,
apt-get, dpkg, yum, rpm, etc.) or adjust PATH environment
variable in your script.' \
		"$tool" "$tool"
	done

	# Reset list of required tools: each script MUST set its own
	# dependency list
	unset -v crt1_request_tools_list
}
declare -fr crt1_request_tools

################################################################################
# Initialization                                                               #
################################################################################

# Path must be first variable, because external tool dependency checker
# uses it to find tools.
export PATH='/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin'

# Ensure tools on which calling script depends found in system
crt1_request_tools "${crt1_request_tools_list[@]}" ${NCTL_RUNAS:+sudo} \
	hostname cat id getent

# Re-exec itself as given user
if [ -z "$NCTL_IN_RUNAS" -a -n "$NCTL_RUNAS" ]; then
	exec sudo -u "$NCTL_RUNAS" NCTL_IN_RUNAS=y "$0" "$@"
	crt1_fatal '' \
'Re-exec itself with `sudo -u "%s" "%s" ...` failed.' \
		"$NCTL_RUNAS" "$0"
fi

### Initialize/Setup common variables

# Set $HOSTNAME if unset or empty
: ${HOSTNAME:="$(hostname -s 2>/dev/null)"}
[ -n "$HOSTNAME" ] || HOSTNAME="$(cat '/proc/sys/kernel/hostname' 2>/dev/null)"

# Set $USER if unset or empty
: ${USER:="$(id -un 2>/dev/null)"}
[ -n "$USER" ] || USER="$(getent passwd "$UID" 2>/dev/null)" && USER="${USER%%:*}"

# Set $LOGNAME, $USERNAME and PID
: ${LOGNAME:="$USER"} ${USERNAME:="$USER"} ${PID:=$$}

# Export common variables
export HOSTNAME USER LOGNAME USERNAME PID

# Program name
program_invocation_name="$0"
program_invocation_short_name="${0##*/}"

# Compatibility progam name without K|S[[:digit:]]+ as with SysV initscripts
prog_name="$program_invocation_short_name"
[ "${prog_name:0:1}" = 'K' -o "${prog_name:0:1}" = 'S' ] &&
	[ "${prog_name:1:2}" -ge 0 ] 2>/dev/null &&
	prog_name="${prog_name:3}"

# Program arguments
argv=("$0" "$@")

### Initialize configuration

# Load configuration file for @this script
crt1_source_cfg "${BASH_SOURCE[0]}"

# Location of the netctl library
: ${NCTL_PREFIX:='@target@/netctl'}

# Netctl library TMPDIR variable
: ${NCTL_TMPDIR:="$NCTL_PREFIX/tmp"}

# Initial exit code
declare -i nctl_rc=0

### Return to the calling script
:
