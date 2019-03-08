#!/bin/bash

[ -z "$__included_libacct_sh" ] || return 0
declare -r __included_libacct_sh=1

# External tool dependencies, MUST always be defined,
# even if empty (e.g.: declare -a crt1_request_tools_list=())
declare -a crt1_request_tools_list=()

# Source startup code
. @target@/netctl/lib/bash/crt1.sh

# Source functions libraries
. @target@/netctl/lib/bash/libfile.sh
. @target@/netctl/lib/bash/liblog.sh

# Control accounting facilities
: ${NCTL_ACCOUNT_ENABLE:=y}

# Append messages to "$NCTL_ACCOUNT_FILE"
: ${NCTL_ACCOUNT_APPEND:=y}
# Account and log to separate files by default.
: ${NCTL_ACCOUNT_FILE:="$NCTL_PREFIX/var/log/$program_invocation_short_name.acct"}
# Log file descriptor of "$NCTL_ACCOUNT_FILE"
nctl_is_valid_fd ${NCTL_ACCOUNT_FD:=-1} || NCTL_ACCOUNT_FD=-1
declare -i NCTL_ACCOUNT_FD

# Usage: nctl_openaccount
nctl_openaccount()
{
	# Is accounting enabled?
	nctl_is_yes "$NCTL_ACCOUNT_ENABLE" || return
	# Open account file
	local NCTL_LOG_FILE_APPEND="$NCTL_ACCOUNT_APPEND"
	local NCTL_LOGFILE="$NCTL_ACCOUNT_FILE"
	local -i NCTL_LOGFILE_FD=$NCTL_ACCOUNT_FD
	nctl_openlog || return
	# Save account file descriptor
	NCTL_ACCOUNT_FD=$NCTL_LOGFILE_FD
}
declare -fr nctl_openaccount

# Usage: nctl_closeaccount
nctl_closeaccount()
{
	local -i NCTL_LOGFILE_FD=$NCTL_ACCOUNT_FD
	# Close account file
	nctl_closelog || return
	# Save invalidated descriptor
	NCTL_ACCOUNT_FD=$NCTL_LOGFILE_FD
}
declare -fr nctl_closeaccount

# Usage: nctl_account <fmt> [<arg1> <arg2> ...]
nctl_account()
{
	local -i rc=$?

	nctl_is_valid_fd $NCTL_ACCOUNT_FD || nctl_openaccount || return $rc

	# Always manually specify locations where we account!
	# These vars might be overwritten by somewhere else in logging subsystem.
	NCTL_LOG_ENABLE=y \
	NCTL_LOG_PREFIX_NONE=n NCTL_LOG_PREFIX_DATE=y NCTL_LOG_PREFIX_PROGNAME=y \
	NCTL_LOG_STD=n NCTL_STD_FD=-1 \
	NCTL_LOG_FILE=y NCTL_LOGFILE_FD=$NCTL_ACCOUNT_FD \
		nctl_log_msg "$@"

	return $rc
}
declare -fr nctl_account
