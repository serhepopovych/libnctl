#!/bin/bash

[ -z "$__included_liblog_sh" ] || return 0
declare -r __included_liblog_sh=1

# External tool dependencies, MUST always be defined,
# even if empty (e.g.: declare -a crt1_request_tools_list=())
declare -a crt1_request_tools_list=(
	'date'		# date(1)
)

# Source startup code
. /netctl/lib/bash/crt1.sh

# Source functions libraries
. /netctl/lib/bash/libbool.sh
. /netctl/lib/bash/libfile.sh
. /netctl/lib/bash/libprocess.sh

# Control logging facilities
: ${NCTL_LOG_ENABLE:=y}

# Log messages and output unmodified to stdout
: ${NCTL_LOG_PIPE_TEE:=n}

# Do not prefix messages
: ${NCTL_LOG_PREFIX_NONE:=n}
nctl_is_yes "$NCTL_LOG_PREFIX_NONE" && NCTL_LOG_PREFIX_PROGNAME=n && NCTL_LOG_PREFIX_DATE=n
# Prefix messages with program name (syslog behavior, default)
: ${NCTL_LOG_PREFIX_PROGNAME:=y}
# Prefix messages with date in format '%b %d %T' (syslog behavior, default)
: ${NCTL_LOG_PREFIX_DATE:=y}

## Log messages to $NCTL_STD_FD file descriptor (default: $NCTL_STDERR)
: ${NCTL_LOG_STD:=n}
# File descriptor to log to
nctl_is_valid_fd ${NCTL_STD_FD:=$NCTL_STDERR} || NCTL_STD_FD=$NCTL_STDERR
declare -i NCTL_STD_FD

## Log messages to file "$NCTL_LOGFILE"
: ${NCTL_LOG_FILE:=y}
# Append messages to "$NCTL_LOGFILE"
: ${NCTL_LOG_FILE_APPEND:=y}
# Log file location
: ${NCTL_LOGFILE:="$NCTL_PREFIX/var/log/$program_invocation_short_name.log"}
# Log file descriptor of "$NCTL_LOGFILE"
nctl_is_valid_fd ${NCTL_LOGFILE_FD:=-1} || NCTL_LOGFILE_FD=-1
declare -i NCTL_LOGFILE_FD

# Usage: nctl_openlog [<logfile>]
nctl_openlog()
{
	# Already opened: reopen
	nctl_closelog || return
	# Nothing to open: return
	local logfile="${1:-$NCTL_LOGFILE}"
	[ -z "$logfile" ] && return
	# Opening
	local -i logfilefd
	local mode
	nctl_is_yes "$NCTL_LOG_FILE_APPEND" && mode='>>' || mode='>'
	nctl_openfile "$logfile" "$mode" '' logfilefd || return
	# Set global info
	NCTL_LOGFILE="$logfile"
	NCTL_LOGFILE_FD=$logfilefd
}
declare -fr nctl_openlog

# Usage: nctl_closelog
nctl_closelog()
{
	# Already closed?
	! nctl_is_valid_fd $NCTL_LOGFILE_FD && return
	# Closing
	nctl_closefile $NCTL_LOGFILE_FD || return
	# Invalidate file descriptor
	NCTL_LOGFILE_FD=-1
}
declare -fr nctl_closelog

# Usage: nctl_log_msg <fmt> [<arg1> <arg2> ...]
# Example: nctl_log_msg 'message'
nctl_log_msg()
{
	local -i rc=$?
	# Should we log anything?
	nctl_is_no "$NCTL_LOG_ENABLE" && return $rc
	local fmt="$1"
	shift
	# Prefix
	if ! nctl_is_yes "$NCTL_LOG_PREFIX_NONE"; then
		# prefix with progname
		nctl_is_yes "$NCTL_LOG_PREFIX_PROGNAME" &&
			fmt="${fmt:+"$program_invocation_short_name: $fmt"}"
		# prefix with date
		nctl_is_yes "$NCTL_LOG_PREFIX_DATE" &&
			fmt="${fmt:+"$(date '+%b %d %T'): $fmt"}"
	fi
	# Log to std
	if nctl_is_yes "$NCTL_LOG_STD"; then
		nctl_is_valid_fd $NCTL_STD_FD || return $rc
		printf "$fmt" "$@" >&$NCTL_STD_FD
	fi
	# Log to file
	if nctl_is_yes "$NCTL_LOG_FILE"; then
		nctl_is_valid_fd $NCTL_LOGFILE_FD || nctl_openlog || return $rc
		printf "$fmt" "$@" >&$NCTL_LOGFILE_FD
	fi
	return $rc
}
declare -fr nctl_log_msg

# Usage: nctl_log_pipe
# Example: echo 'message' |nctl_log_pipe
nctl_log_pipe()
{
	# Should we log anything?
	nctl_is_no "$NCTL_LOG_ENABLE" && return
	# Read from stdin and log messages
	local r
	while IFS= read -r r; do
		nctl_log_msg '%s\n' "$r"
		nctl_is_yes "$NCTL_LOG_PIPE_TEE" && printf '%s\n' "$r"
	done
	return 0
}
declare -fr nctl_log_pipe

# Usage: nctl_log_pipe_tee
# Example: echo 'message' |nctl_log_pipe_tee |cat
nctl_log_pipe_tee()
{
	NCTL_LOG_PIPE_TEE=y nctl_log_pipe
}
declare -fr nctl_log_pipe_tee

# Usage: nctl_check_ok <fmt> [<arg1> <arg2> ...]
nctl_check_ok()
{
	nctl_inc_rc nctl_rc && return

	[ -z "$1" ] || nctl_log_msg "$@"

	exit $nctl_rc
}
declare -fr nctl_check_ok
