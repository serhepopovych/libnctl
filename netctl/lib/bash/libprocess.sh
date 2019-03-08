#!/bin/bash

[ -z "$__included_libprocess_sh" ] || return 0
declare -r __included_libprocess_sh=1

# External tool dependencies, MUST always be defined,
# even if empty (e.g.: declare -a crt1_request_tools_list=())
declare -a crt1_request_tools_list=(
	'rm'		# rm(1)
)

# Source startup code
. @target@/netctl/lib/bash/crt1.sh

# Source functions libraries
. @target@/netctl/lib/bash/libfile.sh
. @target@/netctl/lib/bash/liblog.sh

#
# Basic process management
#

# Standard exit codes
declare -ir NCTL_EXIT_SUCCESS=0 NCTL_EXIT_FAILURE=1

: ${NCTL_PIDFILE:='/var/run/%s.pid'}

# Usage: nctl_pidfile_name [<binary_name>] [<var>]
# Result: return complete name of the pid file made.
#         from NCTL_PIDFILE template.
nctl_pidfile_name()
{
	local nctl_pidfile_name_s="$1"
	local nctl_pidfile_name_var="$2"

	printf \
		${nctl_pidfile_name_var:+-v "$nctl_pidfile_name_var"} \
		"$NCTL_PIDFILE" \
		"${nctl_pidfile_name_s:-$program_invocation_short_name}"
}
declare -fr nctl_pidfile_name

# Usage: nctl_is_running <pid>
# Return: 0 - on success
nctl_is_running()
{
	local -i pid="${1:?missing 1st argument to function \"$FUNCNAME\" (pid)}"

	# Use 0 signal to determine process existence.
	#
	# This performs all checks, implied by the kill(2)
	# without actually sending signal to the process,
	# opening possibility to perform process existence
	# checking.
	#
	# One of the major limitation of such method is
	# that process, using kill(2) should have sufficient
	# privileges to send signal to given process (e.g
	# kill -0 may fail not because process does not
	# exist, but because current process does not have
	# sufficient privileges to send signal to such process).
	#
	# See kill(2) for more information on this
	# special signal value.
	kill -0 $pid &>/dev/null && return

	# In case of process with given pid is running, but
	# current process have insufficient privileges to
	# send signal to the process with pid use procfs on
	# Linux to check if PID exists.
	[ -d "$NCTL_PROC_DIR/$pid" ]
}
declare -fr nctl_is_running

# Usage: nctl_is_running_pidfile <pidfile> [<timeout>]
# Return:0 - on success
nctl_is_running_pidfile()
{
	local p="${1:?missing 1st argument to funcion \"$FUNCNAME\" (pidfile)}"
	local t="$2"

	# Wait for PID file if it does not exists.
	nctl_waitfile "$p" "$t" || return

	# Is file is regular, non-empty, readable file?
	[ -f "$p" -a -s "$p" -a -r "$p" ] || return

	# Read file.
	p="$(<"$p")" || return

	# Make sure it contains only PID.
	[ "$p" -gt 0 ] 2>/dev/null || return

	nctl_is_running "$p"
}
declare -fr nctl_is_running_pidfile

#
# Lock/Unlock subsystem
#

# Subsystem name
declare -r NCTL_SUBSYS_NAME="$program_invocation_short_name"

# Generic lock file to lock whole subsystem
declare -r NCTL_SUBSYS_LOCKFILE="$NCTL_TMPDIR/$NCTL_SUBSYS_NAME.lock"

# Usage: nctl_subsys_lock
nctl_subsys_lock()
{
	local pid

	# Is subsystem already locked?
	if [ -e "$NCTL_SUBSYS_LOCKFILE" ]; then
		# Is regular file?
		if [ -f "$NCTL_SUBSYS_LOCKFILE" ]; then
			# Read PID and check if process is running
			[ ! -s "$NCTL_SUBSYS_LOCKFILE" ] ||
			! nctl_is_running "${pid:=$(<"$NCTL_SUBSYS_LOCKFILE")}" ||
				nctl_log_msg \
					'%s already running as %s: exiting\n' \
					"$NCTL_SUBSYS_NAME" \
					"$pid" ||
				return 254
			# Stale lockfile: report, remove and continue
			rm -f "$NCTL_SUBSYS_LOCKFILE" ||
				nctl_log_msg \
					'can not remove lock file %s!!!\n' \
					"$NCTL_SUBSYS_LOCKFILE" ||
				return 254
			# Report lockfile removal and continue
			nctl_log_msg \
'%s not running, but lockfile exists: lock removed, continue\n' \
				"$NCTL_SUBSYS_NAME"
		else
			nctl_log_msg \
'%s is not regular file, remove it manually and restart %s subsystem: exiting\n' \
				"$NCTL_SUBSYS_LOCKFILE" \
				"$NCTL_SUBSYS_NAME" ||
			return
		fi
	fi

	# Lock subsystem
	printf '%s\n' "$PID" 2>&1 >"$NCTL_SUBSYS_LOCKFILE" |nctl_log_pipe ||
		nctl_log_msg 'unable to lock subsystem: exiting\n' ||
		return 254
}
declare -fr nctl_subsys_lock

# Usage: nctl_subsys_unlock
nctl_subsys_unlock()
{
	local pid

	# Is subsystem already unlocked?
	[ -e "$NCTL_SUBSYS_LOCKFILE" ] ||
		nctl_log_msg 'subsystem unlocked. %s does not exists!\n' \
			"$NCTL_SUBSYS_LOCKFILE" || return 0

	# Is regular file?
	[ -f "$NCTL_SUBSYS_LOCKFILE" ] ||
		nctl_log_msg '%s is not regular file: will not unlock\n' \
			"$NCTL_SUBSYS_LOCKFILE" || return

	# Is non-empty file?
	[ -s "$NCTL_SUBSYS_LOCKFILE" ] ||
		nctl_log_msg '%s is empty: will not unlock\n' \
			"$NCTL_SUBSYS_LOCKFILE" || return

	# Is locked by our process?
	[ "${pid:=$(<"$NCTL_SUBSYS_LOCKFILE")}" = "$PID" ] ||
		nctl_log_msg \
'%s has %s pid, but our is %s: locked by some one else: will not unlock\n' \
			"$NCTL_SUBSYS_LOCKFILE" "$pid" "$PID" || return

	# Unlock subsystem
	rm -f "$NCTL_SUBSYS_LOCKFILE" 2>&1 |nctl_log_pipe ||
		nctl_log_msg 'unable to unlock subsystem: exiting\n'
}
declare -fr nctl_subsys_unlock
