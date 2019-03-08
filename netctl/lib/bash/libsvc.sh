#!/bin/bash

[ -z "$__included_libsvc_sh" ] || return 0
declare -r __included_libsvc_sh=1

# External tool dependencies, MUST always be defined,
# even if empty (e.g.: declare -a crt1_request_tools_list=())
declare -a crt1_request_tools_list=(
	'start-stop-daemon'		# start-stop-daemon(8)
	'cpulimit'			# cpulimit(1)
	'getopt'			# getopt(1)
	'rm'				# rm(1)
)

# Source startup code
. @target@/netctl/lib/bash/crt1.sh

# Source functions library
. @target@/netctl/lib/bash/libbool.sh
. @target@/netctl/lib/bash/librtti.sh
. @target@/netctl/lib/bash/libiter.sh
. @target@/netctl/lib/bash/libstring.sh
. @target@/netctl/lib/bash/libfile.sh
. @target@/netctl/lib/bash/libprocess.sh
. @target@/netctl/lib/bash/libnss.sh

# SysV Debian/Ubuntu initscripts function library
declare -F log_daemon_msg &>/dev/null || . /lib/lsb/init-functions

##
## Overwrite/extend netctl libraries functionality
##

# Usage: nctl_svc_get_default_val <var_name_full> [<var>]
nctl_svc_get_default_val()
{
	local nctl_svc_get_default_val_var_name_full="DEFAULT_${1}"
	shift
	local -i rc=0

	nctl_svc_get_default_val__nctl_get_val_check()
	{
		nctl_get_val_check_non_empty "$@"
	}
	nctl_get_val_check='nctl_svc_get_default_val__nctl_get_val_check' \
		nctl_get_val "$nctl_svc_get_default_val_var_name_full" "$@" ||
	nctl_inc_rc rc

	# Remove internal function from global namespace
	unset -f nctl_svc_get_default_val__nctl_get_val_check

	return $rc
}
declare -fr nctl_svc_get_default_val

# Usage: nctl_svc_get_val_check <var_name_full>
nctl_svc_get_val_check()
{
	nctl_get_val_check_non_empty "$@" && return

	local -a nctl_svc_get_val_check_val
	nctl_svc_get_default_val "$1" nctl_svc_get_val_check_val &&
		nctl_set_val nctl_get_val_val "${nctl_svc_get_val_check_val[@]}"
}
declare -fr nctl_svc_get_val_check

nctl_get_val_check='nctl_svc_get_val_check'

# Usage: nctl_svc_check_nss_entry <var_get> <db> [<var>]
nctl_svc_check_nss_entry()
{
	local nctl_svc_check_nss_entry_var_get="${1:?missing 1st argument to function \"$FUNCNAME\" (var_get)}"
	local nctl_svc_check_nss_entry_db="${2:?missing 2d argument to function \"$FUNCNAME\" (db)}"
	local nctl_svc_check_nss_entry_var="$3"
	local nctl_svc_check_nss_entry_s
	shift

	# Try to get normal variable first, then DEFAULT_* variable next.
	# Report success if none was available.
	nctl_get_val \
		"$nctl_svc_check_nss_entry_var_get" \
		nctl_svc_check_nss_entry_s ||
	nctl_svc_get_default_val \
		"$nctl_svc_check_nss_entry_var_get" \
		nctl_svc_check_nss_entry_s || return 0

	nctl_check_nss_entry "$nctl_svc_check_nss_entry_s" "$@"
}
declare -fr nctl_svc_check_nss_entry

##
## Service iterators
##

# Usage: nctl_svc_action_for_each <msg> <action> <svc_name1> <svc_name2> ...
nctl_svc_action_for_each()
{
	local msg="${1:?missing 1st argument to function \"$FUNCNAME\" (msg)}"
	shift
	local -i rc=0

	nctl_is_yes "$NCTL_SVC_QUIET" || log_daemon_msg "$msg"
	nctl_action_for_each "$@" || nctl_inc_rc rc
	nctl_is_yes "$NCTL_SVC_QUIET" || log_end_msg $rc

	return $rc
}
declare -fr nctl_svc_action_for_each

# Usage: nctl_svc_action_for_each_in_svc_list <action>
nctl_svc_action_for_each_in_svc_list()
{
	nctl_action_for_each "$1" $NCTL_SVC_LIST
}
declare -fr nctl_svc_action_for_each_in_svc_list

##
## cpulimit(1) start/stop helpers
##

# Usage: nctl_svc_pidfile_from_opts optstring -- { $SNMPDOPTS | $TRAPDOPTS }
# Return: absolute path to pidfile specified in opts
nctl_svc_pidfile_from_opts()
{
	local o="${1:?missing 1st argument to function \"$FUNCNAME\" (optstring)}"
	local pf=
	shift 2
	eval set -- `getopt -qo"$o" -- "$@" 2>/dev/null`
	while [ -n "$1" ]; do
		case "$1" in
			-p)
				pf="$2"
				break
				;;
		esac
		shift
	done
	[ -n "$pf" ] && printf '%s' "$pf"
}
declare -fr nctl_svc_pidfile_from_opts

# Usage: nctl_svc_pid_from_opts optstring -- { $SNMPDOPTS | $TRAPDOPTS }
# Return: PID found in file
nctl_svc_pid_from_opts()
{
	local p
	p="$(nctl_svc_pidfile_from_opts "$@")" && nctl_is_running_pidfile "$p" && cat "$p"
}
declare -fr nctl_svc_pid_from_opts

# Usage: nctl_start_cpulimit <pidfile_of_the_process_to_control> [<uid>] [<gid>] -- [ cpulimit options ]
# Return: 0 - on success
nctl_start_cpulimit()
{
	local CPULIMIT
	local pf="${1:?missing 1st argument to funcion \"$FUNCNAME\" (pidfile_of_the_process_to_control)}"
	local p
	local uid gid

	# Take absolute path to the cpulimit(1)
	nctl_absolute 'cpulimit' CPULIMIT || return

	# is controlling process is running?
	nctl_is_running_pidfile "$pf" 60 || return

	# is there uid/gid specified?
	if [ "$2" != '--' ]; then
		uid="$2"
		shift
		if [ "$2" != '--' ]; then
			gid="$2"
			shift
		fi
	fi
	shift 2

	p="$(<"$pf")"
	pf="${pf%.pid}-cpulimit.pid"
	# uid == chuid option
	uid="$uid${gid:+:$gid}"

	start-stop-daemon --quiet --start --oknodo --exec "$CPULIMIT" \
		--make-pidfile --background --pidfile "$pf" \
		${uid:+--chuid "$uid"} --group proc \
		-- -p"$p" -z "$@"
}
declare -fr nctl_start_cpulimit

# Usage: nctl_stop_cpulimit <pidfile_of_the_process_to_control>
# Return: 0 - on success
nctl_stop_cpulimit()
{
	local CPULIMIT
	local pf="${1:?missing 1st argument to funcion \"$FUNCNAME\" (pidfile_of_the_process_to_control)}"
	pf="${pf%.pid}-cpulimit.pid"

	# Take absolute path to the cpulimit(1)
	nctl_absolute 'cpulimit' CPULIMIT || return

	start-stop-daemon --quiet --stop --oknodo --exec "$CPULIMIT" \
		--pidfile "$pf"
	rm -f "$pf"
}
declare -fr nctl_stop_cpulimit

##
## Daemon start/stop helpers
##

# Usage: nctl_svc_do_common <action> <svc_name> ...
nctl_svc_do_common()
{
	local action="${1:?missing 1st argument to function \"$FUNCNAME\" (action)}"
	local svc_name="${2:?missing 2d argument to function \"$FUNCNAME\" (svc_name)}"
	shift 2
	local var_name
	# Make return code global for helpers
	local -i nctl_svc_do_rc=0

	nctl_str2sh_var "$svc_name" var_name
	nctl_strtoupper "$var_name" var_name

	# Check if service RUN
	! nctl_svc_is_may_run $nctl_svc_is_may_run_var_name "$var_name" && return

	local nctl_svc_do_action_pre
	local nctl_svc_do_action_daemon
	local nctl_svc_do_action_post

	# pre
	nctl_get_val "nctl_svc_do_${action}_pre" nctl_svc_do_action_pre &&
	nctl_arg_is_function "$nctl_svc_do_action_pre" || return

	# daemon
	nctl_get_val "nctl_svc_do_${action}_daemon" nctl_svc_do_action_daemon &&
	nctl_arg_is_function "$nctl_svc_do_action_daemon" || return

	# post
	nctl_get_val "nctl_svc_do_${action}_post" nctl_svc_do_action_post &&
	nctl_arg_is_function "$nctl_svc_do_action_post" || return

	# Execute action(s)
	"$nctl_svc_do_action_pre" "$svc_name" "$var_name" "$@" ||
		nctl_inc_rc nctl_svc_do_rc
	"$nctl_svc_do_action_daemon" "$svc_name" "$var_name" "$@" ||
		nctl_inc_rc nctl_svc_do_rc
	"$nctl_svc_do_action_post" "$svc_name" "$var_name" ||
		nctl_inc_rc nctl_svc_do_rc

	return $nctl_svc_do_rc
}
declare -fr nctl_svc_do_common

# Usage: __nctl_svc_do <action> <svc_name> ...
__nctl_svc_do()
{
	# Call common action
	nctl_svc_do_common "$@"
}
declare -fr __nctl_svc_do

# Call default (inherit)
: ${nctl_svc_do:='__nctl_svc_do'}

# Usage: nctl_svc_do_is_failed
nctl_svc_do_is_failed()
{
	[ $nctl_svc_do_rc -ne 0 ]
}
declare -fr nctl_svc_do_is_failed

# Usage: __nctl_svc_run_action <title> <action> <svc_name1> <svc_name2> ...
__nctl_svc_run_action()
{
	local title="${1:?missing 1st argument to function \"$FUNCNAME\" (title)}"
	local action="${2:?missing 2d argument to function \"$FUNCNAME\" (action)}"
	shift 2

	nctl_str2sh_var "$action" action &&
	nctl_get_val "nctl_svc_$action" action &&
	nctl_arg_is_function "$action" || return

	# Execute action
	"$action" "$title" "$@"
}
declare -fr __nctl_svc_run_action

# Call default (inherit)
: ${nctl_svc_run_action:='__nctl_svc_run_action'}

#
# Start
#

# Usage: __nctl_svc_do_start_pre <svc_name> <var_name> ...
__nctl_svc_do_start_pre()
{
	local svc_name="$1"
	local var_name="$2"
	shift 2

	nctl_is_yes "$NCTL_SVC_QUIET" || log_progress_msg "$svc_name"

	return 0
}
declare -fr __nctl_svc_do_start_pre

# Call default (inherit)
: ${nctl_svc_do_start_pre:='__nctl_svc_do_start_pre'}

# Usage: __nctl_svc_do_start_post <svc_name> <var_name> ...
__nctl_svc_do_start_post()
{
	local svc_name="$1"
	local var_name="$2"
	shift 2
	local pid cpulimit_opts

	nctl_svc_do_is_failed && return

	# Get variables values
	nctl_get_val "CPULIMIT_OPTS_${var_name}" cpulimit_opts

	# Start cpulimit for service if required
	if [ -n "$cpulimit_opts" ]; then
		nctl_get_val "${var_name}_USER" user
		nctl_get_val "${var_name}_GROUP" group
		nctl_get_val "${var_name}_PID" pid

		nctl_start_cpulimit "$pid" "$user" "$group" -- $cpulimit_opts
	fi
}
declare -fr __nctl_svc_do_start_post

# Call default (inherit)
: ${nctl_svc_do_start_post:='__nctl_svc_do_start_post'}

# Usage: __nctl_svc_do_start_daemon <svc_name> <var_name> ...
__nctl_svc_do_start_daemon()
{
	local svc_name="$1"
	local var_name="$2"
	shift 2
	local bin pid opts

	nctl_svc_do_is_failed && return

	# Get variables values
	nctl_get_val "${var_name}_BIN" bin
	nctl_get_val "${var_name}_PID" pid
	nctl_get_val "${var_name}_OPTS" opts

	# Start daemon
	start-stop-daemon --quiet --start --oknodo \
		--exec "$bin" --pidfile "$pid" "$@" -- $opts
}
declare -fr __nctl_svc_do_start_daemon

# Call default (inherit)
: ${nctl_svc_do_start_daemon:='__nctl_svc_do_start_daemon'}

# Usage: __nctl_svc_do_start <svc_name> ...
__nctl_svc_do_start()
{
	local svc_name="$1"
	shift

	nctl_arg_is_function "$nctl_svc_do" || return

	"$nctl_svc_do" start "$svc_name" "$@"
}
declare -fr __nctl_svc_do_start

# Call default (inherit)
: ${nctl_svc_do_start:='__nctl_svc_do_start'}

# Usage: __nctl_svc_start <title> <svc_name1> <svc_name2> ...
__nctl_svc_start()
{
	local title="$1"
	shift

	nctl_svc_action_for_each "Starting $title services" "$nctl_svc_do_start" "$@"
}
declare -fr __nctl_svc_start

# Call default (inherit)
: ${nctl_svc_start:='__nctl_svc_start'}

#
# Stop
#

# Usage: __nctl_svc_do_stop_pre <svc_name> <var_name> ...
__nctl_svc_do_stop_pre()
{
	local svc_name="$1"
	local var_name="$2"
	shift 2
	local pid

	nctl_is_yes "$NCTL_SVC_QUIET" || log_progress_msg "$svc_name"

	# Get variables varlues
	nctl_get_val "${var_name}_PID" pid

	# Stop cpulimit for service if started previously
	if [ -n "$pid" ]; then
		nctl_stop_cpulimit "$pid"
	fi

	return 0
}
declare -fr __nctl_svc_do_stop_pre

# Call default (inherit)
: ${nctl_svc_do_stop_pre:='__nctl_svc_do_stop_pre'}

# Usage: __nctl_svc_do_stop_post <svc_name> <var_name> ...
__nctl_svc_do_stop_post()
{
	local svc_name="$1"
	local var_name="$2"
	shift 2
	local pid

	# We do not check for failed previous helper as we need
	# to perform ALL helpers in 'stop' stage, even if same
	# of them failed.

	# Get variables varlues
	nctl_get_val "${var_name}_PID" pid

	# Remove stale pid file
	rm -f "$pid" &>/dev/null

	return 0
}
declare -fr __nctl_svc_do_stop_post

# Call default (inherit)
: ${nctl_svc_do_stop_post:='__nctl_svc_do_stop_post'}

# Usage: __nctl_svc_do_stop_daemon <svc_name> <var_name> ...
__nctl_svc_do_stop_daemon()
{
	local svc_name="$1"
	local var_name="$2"
	shift 2
	local bin pid

	# We do not check for failed previous helper as we need
	# to perform ALL helpers in 'stop' stage, even if same
	# of them failed.

	# Get variables varlues
	nctl_get_val "${var_name}_BIN" bin
	nctl_get_val "${var_name}_PID" pid

	# Stop daemon
	start-stop-daemon --quiet --stop --oknodo --retry=TERM/30/KILL/5 \
		--exec "$bin" ${pid:+--pidfile "$pid"} "$@"

	return 0
}
declare -fr __nctl_svc_do_stop_daemon

# Call default (inherit)
: ${nctl_svc_do_stop_daemon:='__nctl_svc_do_stop_daemon'}

# Usage: __nctl_svc_do_stop <svc_name> ...
__nctl_svc_do_stop()
{
	local svc_name="$1"
	shift

	nctl_arg_is_function "$nctl_svc_do" || return

	local var_name

	nctl_str2sh_var "$svc_name" var_name
	nctl_strtoupper "$var_name" var_name

	# For stop action serivce is always RUN
	eval \
	 	"${var_name}_RUN='yes'" \
		"$nctl_svc_do" stop "$svc_name" "$@"

	return 0
}
declare -fr __nctl_svc_do_stop

# Call default (inherit)
: ${nctl_svc_do_stop:='__nctl_svc_do_stop'}

# Usage: __nctl_svc_stop <title> <svc_name1> <svc_name2> ...
__nctl_svc_stop()
{
	local title="$1"
	shift

	nctl_svc_action_for_each "Stopping $title services" "$nctl_svc_do_stop" "$@"
}
declare -fr __nctl_svc_stop

# Call default (inherit)
: ${nctl_svc_stop:='__nctl_svc_stop'}

#
# Restart
#

# Usage: __nctl_svc_restart <title> <svc_name1> <svc_name2> ...
__nctl_svc_restart()
{
	nctl_arg_is_function "$nctl_svc_start" &&
	nctl_arg_is_function "$nctl_svc_stop" || return

	"$nctl_svc_stop" "$@"
	sleep 2
	"$nctl_svc_start" "$@"
}
declare -fr __nctl_svc_restart

# Call default (inherit)
: ${nctl_svc_restart:='__nctl_svc_restart'}

#
# Reload
#

# Usage: __nctl_svc_do_reload_pre <svc_name> <var_name> ...
__nctl_svc_do_reload_pre()
{
	local svc_name="$1"
	local var_name="$2"
	shift 2

	nctl_is_yes "$NCTL_SVC_QUIET" || log_progress_msg "$svc_name"

	return 0
}
declare -fr __nctl_svc_do_reload_pre

# Call default (inherit)
: ${nctl_svc_do_reload_pre:='__nctl_svc_do_reload_pre'}

# Usage: __nctl_svc_do_reload_post <svc_name> <var_name> ...
__nctl_svc_do_reload_post()
{
	local svc_name="$1"
	local var_name="$2"
	shift 2

	nctl_svc_do_is_failed && return

	return 0
}
declare -fr __nctl_svc_do_reload_post

# Call default (inherit)
: ${nctl_svc_do_reload_post:='__nctl_svc_do_reload_post'}

# Usage: __nctl_svc_do_reload_daemon <svc_name> <var_name> ...
__nctl_svc_do_reload_daemon()
{
	local svc_name="$1"
	local var_name="$2"
	shift 2
	local bin pid

	nctl_svc_do_is_failed && return

	# Get variables values
	nctl_get_val "${var_name}_BIN" bin
	nctl_get_val "${var_name}_PID" pid

	# Reload daemon
	start-stop-daemon --quiet --stop --oknodo --signal HUP \
		--exec "$bin" --pidfile "$pid" "$@"
}
declare -fr __nctl_svc_do_reload_daemon

# Call default (inherit)
: ${nctl_svc_do_reload_daemon:='__nctl_svc_do_reload_daemon'}

# Usage: __nctl_svc_do_reload <svc_name> ...
__nctl_svc_do_reload()
{
	local svc_name="$1"
	shift

	nctl_arg_is_function "$nctl_svc_do" || return

	"$nctl_svc_do" reload "$svc_name" "$@"
}
declare -fr __nctl_svc_do_reload

# Call default (inherit)
: ${nctl_svc_do_reload:='__nctl_svc_do_reload'}

# Usage: __nctl_svc_reload <title> <svc_name1> <svc_name2> ...
__nctl_svc_reload()
{
	local title="$1"
	shift

	nctl_svc_action_for_each "Reloading $title services" "$nctl_svc_do_reload" "$@"
}
declare -fr __nctl_svc_reload

# Call default (inherit)
: ${nctl_svc_reload:='__nctl_svc_reload'}

#
# Forced Reload
#

# Usage: __nctl_svc_force_reload <title> <svc_name1> <svc_name2> ...
__nctl_svc_force_reload()
{
	nctl_arg_is_function "$nctl_svc_reload" || return

	"$nctl_svc_reload" "$@"
}
declare -fr __nctl_svc_force_reload

# Call default (inherit)
: ${nctl_svc_force_reload:='__nctl_svc_force_reload'}

#
# Check
#

declare -ir \
	nctl_svc_check_ok=0 \
	nctl_svc_check_failed=1 \
	nctl_svc_check_ignored=254 \
	nctl_svc_check_unknown=255

declare -ar nctl_svc_check_msgs=(
	[$nctl_svc_check_ok]='ok'
	[$nctl_svc_check_failed]='failed'
	[$nctl_svc_check_ignored]='ignored'
	[$nctl_svc_check_unknown]='unknown'
)

declare -ir \
	nctl_svc_is_may_run_svc_name=0 \
	nctl_svc_is_may_run_var_name=1 \
	nctl_svc_is_may_run_var_name_full=2

# Usage: nctl_svc_is_may_run <var_type> <svc_name>|<var_name>|<var_name_full>
nctl_svc_is_may_run()
{
	local -i var_type="${1:?missing 1st argument to function \"$FUNCNAME\" (var_type)}"
	local var_name="${2:?missing 2d argument to function \"$FUNCNAME\" (var_name)}"
	local run

	case $var_type in
		$nctl_svc_is_may_run_svc_name)
			# Service name
			nctl_str2sh_var "$var_name" var_name
			nctl_strtoupper "$var_name" var_name
			var_name="${var_name}_RUN"
			;;
		$nctl_svc_is_may_run_var_name)
			# Service variable name, based on service name
			var_name="${var_name}_RUN"
			;;
		$nctl_svc_is_may_run_var_name_full)
			# Full name of the RUN variable
			;;
		*)
			# Invalid, mark as 'unknown' status of check
			return $nctl_svc_check_unknown
			;;
	esac

	# Get value
	nctl_get_val "$var_name" run
	nctl_is_yes "$run"
}
declare -fr nctl_svc_is_may_run

# Usage: nctl_svc_is_svc_dir <svc_name> <dir> [<var>]
nctl_svc_is_svc_dir()
{
	local nctl_svc_is_svc_dir_svc_name="${1:?missing 1st argument to function \"$FUNCNAME\" (svc_name)}"
	local nctl_svc_is_svc_dir_dir="${2:?missing 1st argument to function \"$FUNCNAME\" (dir)}"
	local nctl_svc_is_svc_dir_var="$3"
	local nctl_svc_is_svc_dir_d

	nctl_fs_path_clean "$nctl_svc_is_svc_dir_dir" nctl_svc_is_svc_dir_dir
	nctl_svc_is_svc_dir_d="${nctl_svc_is_svc_dir_dir##*/}"
	nctl_svc_is_svc_dir_d="${nctl_svc_is_svc_dir_d:-/}"

	[ "$nctl_svc_is_svc_dir_d" = "$nctl_svc_is_svc_dir_svc_name" ] &&
		nctl_return "$nctl_svc_is_svc_dir_var" "$nctl_svc_is_svc_dir_dir"
}
declare -fr nctl_svc_is_svc_dir

# Usage: nctl_svc_check_run_vars <svc_name> [<var_name>] ...
nctl_svc_check_run_vars()
{
	local svc_name="${1:?missing 1st argument to function \"$FUNCNAME\" (name)}"
	local var_name="$2"
	shift 2

	if [ -z "$var_name" ]; then
		nctl_str2sh_var "$svc_name" var_name
		nctl_strtoupper "$var_name" var_name
	fi

	# pid & bin is a must for "stop" where we treat each service
	# as running even if it is not.
	#
	# We set variable(s), but check for their contents validity only
	# for services with RUN.
	local pid bin

	# pid
	nctl_get_val "${var_name}_PID" pid
	[ -n "$pid" ] || nctl_pidfile_name "$svc_name" pid
	nctl_set_val "${var_name}_PID" "$pid"

	# bin
	nctl_get_val "${var_name}_BIN" bin
	nctl_absolute "${bin:-$svc_name}" bin
	nctl_set_val "${var_name}_BIN" "$bin"

	if ! nctl_svc_is_may_run $nctl_svc_is_may_run_var_name "$var_name"; then
		nctl_set_val "${var_name}_RUN" 'no'
		# Return special code to indicate non-fatal error, meaning
		# than no further processing should be made for given service
		return $nctl_svc_check_ignored
	fi

	# check
	[ -x "$bin" -a \( -z "$pid" -o -d "$(nctl_top_dir_name "$pid")" \) ]
}
declare -fr nctl_svc_check_run_vars

# Usage: nctl_svc_check_common_vars <svc_name> [<var_name>] ...
nctl_svc_check_common_vars()
{
	local svc_name="${1:?missing 1st argument to function \"$FUNCNAME\" (svc_name)}"
	local var_name="$2"
	shift 2

	if [ -z "$var_name" ]; then
		nctl_str2sh_var "$svc_name" var_name
		nctl_strtoupper "$var_name" var_name
	fi

	# Do anything only on service that going to start
	! nctl_svc_is_may_run $nctl_svc_is_may_run_var_name "$var_name" &&
		return $nctl_svc_check_ignored

	local var
	local user group dir d_perm file f_perm

	# user
	var="${var_name}_USER"
	nctl_svc_check_nss_entry "$var" 'passwd' user || return
	nctl_set_val "$var" "$user"

	# group
	var="${var_name}_GROUP"
	nctl_svc_check_nss_entry "$var" 'group' group || return
	nctl_set_val "$var" "$group"

	# dir
	var="${var_name}_CONF_DIR"
	nctl_get_val "$var" dir
	[ -z "$dir" -o -d "$dir" ] || return
	nctl_set_val "$var" "$dir"

	# d_perm
	# TODO: implement permission format validation
	var="${var_name}_CONF_DIR_PERM"
	nctl_get_val "$var" d_perm
	nctl_set_val "$var" "$d_perm"

	# file
	var="${var_name}_CONF_FILE"
	nctl_get_val "$var" file
	[ -z "$file" -o -f "$file" ] || return
	nctl_set_val "$var" "$file"

	# f_perm
	# TODO: implement permission format validation
	var="${var_name}_CONF_FILE_PERM"
	nctl_get_val "$var" f_perm
	nctl_set_val "$var" "$f_perm"

	return 0
}
declare -fr nctl_svc_check_common_vars

# Usage: __nctl_svc_check_initscript_vars <svc_name> [<var_name>] ...
__nctl_svc_check_initscript_vars()
{
	local svc_name="${1?:missing 1st argument to function \"$FUNCNAME\" (svc_name)}"
	local var_name="$2"
	shift 2

	nctl_svc_check_run_vars "$svc_name" "$var_name" "$@" &&
	nctl_svc_check_common_vars "$svc_name" "$var_name" "$@"
}
declare -fr __nctl_svc_check_initscript_vars

# Call default (inherit)
: ${nctl_svc_check_initscript_vars:='__nctl_svc_check_initscript_vars'}

# Usage: nctl_svc_check_dentries_common <svc_name> [<var_name>] ...
nctl_svc_check_dentries_common()
{
	local svc_name="${1:?missing 1st argument to function \"$FUNCNAME\" (svc_name)}"
	local var_name="$2"
	shift 2

	if [ -z "$var_name" ]; then
		nctl_str2sh_var "$svc_name" var_name
		nctl_strtoupper "$var_name" var_name
	fi

	# Do anything only on service that going to start
	! nctl_svc_is_may_run $nctl_svc_is_may_run_var_name "$var_name" &&
		return $nctl_svc_check_ignored

	# No action currently

	return 0
}
declare -fr nctl_svc_check_dentries_common

# Usage: __nctl_svc_check_dentries <svc_name> [<var_name>] ...
__nctl_svc_check_dentries()
{
	local svc_name="${1:?missing 1st argument to function \"$FUNCNAME\" (svc_name)}"
	local var_name="$2"
	shift 2

	# Do not check permissions/ownership by default
	return 0
}
declare -fr __nctl_svc_check_dentries

: ${nctl_svc_check_dentries:='__nctl_svc_check_dentries'}

# Usage: nctl_svc_update_dentries_common <svc_name> [<var_name>] ...
nctl_svc_update_dentries_common()
{
	local svc_name="${1:?missing 1st argument to function \"$FUNCNAME\" (svc_name)}"
	local var_name="$2"
	shift 2

	if [ -z "$var_name" ]; then
		nctl_str2sh_var "$svc_name" var_name
		nctl_strtoupper "$var_name" var_name
	fi

	# Do anything only on service that going to start
	! nctl_svc_is_may_run $nctl_svc_is_may_run_var_name "$var_name" &&
		return $nctl_svc_check_ignored

	local user group dir d_perm file f_perm

	# user
	nctl_get_val "${var_name}_USER" user
	# group
	nctl_get_val "${var_name}_GROUP" group
	# dir
	nctl_get_val "${var_name}_CONF_DIR" dir
	# d_perm
	nctl_get_val "${var_name}_CONF_DIR_PERM" d_perm
	# file
	nctl_get_val "${var_name}_CONF_FILE" file
	# f_perm
	nctl_get_val "${var_name}_CONF_FILE_PERM" f_perm

	# Sanity check: do not allow to change permissions/ownership on
	# directory if its name is not the same as service name
	# (e.g.: /, /etc, ...)
	[ -z "$dir" ] || nctl_svc_is_svc_dir "$svc_name" "$dir" dir && [ -d "$dir" ] || dir=

	nctl_update_dentries "$user" "$group" "$f_perm" "$d_perm" "$dir" "$file" "$@"
}
declare -fr nctl_svc_update_dentries_common

# Usage: __nctl_svc_update_dentries <svc_name> [<var_name>] ...
__nctl_svc_update_dentries()
{
	local svc_name="${1:?missing 1st argument to function \"$FUNCNAME\" (svc_name)}"
	local var_name="$2"
	shift 2

	# Do not update permissions/ownership by default
	return 0
}
declare -fr __nctl_svc_update_dentries

: ${nctl_svc_update_dentries:='__nctl_svc_update_dentries'}

# Usage: __nctl_svc_do_check_pre <svc_name> <var_name> ...
__nctl_svc_do_check_pre()
{
	local svc_name="$1"
	local var_name="$2"
	shift 2

	nctl_arg_is_function "$nctl_svc_check_initscript_vars" || return
	nctl_arg_is_function "$nctl_svc_check_dentries" || return
	nctl_arg_is_function "$nctl_svc_update_dentries" || return

	"$nctl_svc_check_initscript_vars" "$svc_name" "$var_name" "$@" &&
	"$nctl_svc_check_dentries" "$svc_name" "$var_name" "$@" &&
	"$nctl_svc_update_dentries" "$svc_name" "$var_name" "$@"
}
declare -fr __nctl_svc_do_check_pre

# Call default (inherit)
: ${nctl_svc_do_check_pre:='__nctl_svc_do_check_pre'}

# Usage: __nctl_svc_do_check_post <svc_name> <var_name> ...
__nctl_svc_do_check_post()
{
	local svc_name="$1"
	local var_name="$2"
	shift 2

	# Print status unless quiet
	if ! nctl_is_yes "$NCTL_SVC_QUIET"; then
		local -i rc=$nctl_svc_do_rc

		# Check bounds before accessing array: value must not be empty
		nctl_is_empty_var nctl_svc_check_msgs $rc &&
			rc=$nctl_svc_check_unknown

		printf '  %16s : %s\n' \
			"$svc_name" "${nctl_svc_check_msgs[$rc]}"
	fi

	return 0
}
declare -fr __nctl_svc_do_check_post

# Call default (inherit)
: ${nctl_svc_do_check_post:='__nctl_svc_do_check_post'}

# Usage: __nctl_svc_do_check_daemon <svc_name> <var_name> ...
__nctl_svc_do_check_daemon()
{
	local svc_name="$1"
	local var_name="$2"
	shift 2

	nctl_svc_do_is_failed && return

	return 0
}
declare -fr __nctl_svc_do_check_daemon

# Call default (inherit)
: ${nctl_svc_do_check_daemon:='__nctl_svc_do_check_daemon'}

# Usage: __nctl_svc_do_check <svc_name> ...
__nctl_svc_do_check()
{
	local svc_name="$1"
	shift

	nctl_arg_is_function "$nctl_svc_do" || return

	"$nctl_svc_do" check "$svc_name" "$@"
}
declare -fr __nctl_svc_do_check

# Call default (inherit)
: ${nctl_svc_do_check:='__nctl_svc_do_check'}

# Usage: __nctl_svc_check <title> <svc_name1> <svc_name2> ...
__nctl_svc_check()
{
	local title="$1"
	shift

	# Implement custom message output subsystem, separated from SysV initscripts one
	nctl_is_yes "$NCTL_SVC_QUIET" || printf 'Checking %s configuratin:\n' "$title"
	nctl_action_for_each "$nctl_svc_do_check" "$@"
}
declare -fr __nctl_svc_check

# Call default (inherit)
: ${nctl_svc_check:='__nctl_svc_check'}

#
# Status
#

declare -ir \
	nctl_svc_daemon_status_running=0 \
	nctl_svc_daemon_status_not_running_but_pid_exists=1 \
	nctl_svc_daemon_status_not_running=3 \
	nctl_svc_daemon_status_unable_to_determine=4 \
	nctl_svc_daemon_status_unknown=5

# See start-stop-daemon(8) for status exit codes
declare -ar nctl_svc_daemon_status_msgs=(
	[$nctl_svc_daemon_status_running]='running'
	[$nctl_svc_daemon_status_not_running_but_pid_exists]='not running, but pid file exists'
	[$nctl_svc_daemon_status_not_running]='not running'
	[$nctl_svc_daemon_status_unable_to_determine]='unable to determine status'
	# Special status: used for new exit codes returned by start-stop-daemon(8)
	[$nctl_svc_daemon_status_unknown]='unknown'
)

# Usage: nctl_svc_get_daemon_status_common <absolute_path_to_bin> <pid_file> ...
nctl_svc_get_daemon_status_common()
{
	local bin="${1:?missing 1st argument to function \"$FUNCNAME\" (absolute_path_to_bin)}"
	local pid="${2:?missing 2d argument to function \"$FUNCNAME\" (pid_file)}"
	shift 2

	start-stop-daemon --quiet --status --exec "$bin" --pidfile "$pid" "$@"
}
declare -fr nctl_svc_get_daemon_status_common

# Usage: __nctl_svc_get_daemon_status <svc_name> [<var_name>] ...
__nctl_svc_get_daemon_status()
{
	local svc_name="${1:?missing 1st argument to function \"$FUNCNAME\" (svc_name)}"
	local var_name="$2"
	shift 2

	if [ -z "$var_name" ]; then
		nctl_str2sh_var "$svc_name" var_name
		nctl_strtoupper "$var_name" var_name
	fi

	local bin pid

	# Get variables values
	nctl_get_val "${var_name}_BIN" bin
	nctl_get_val "${var_name}_PID" pid

	# Call common actin
	nctl_svc_get_daemon_status_common "$bin" "$pid" "$@"
}
declare -fr __nctl_svc_get_daemon_status

: ${nctl_svc_get_daemon_status:='__nctl_svc_get_daemon_status'}

# Usage: __nctl_svc_do_status_pre <svc_name> <var_name> ...
__nctl_svc_do_status_pre()
{
	local svc_name="$1"
	local var_name="$2"
	shift 2

	return 0
}
declare -fr __nctl_svc_do_status_pre

# Call default (inherit)
: ${nctl_svc_do_status_pre:='__nctl_svc_do_status_pre'}

# Usage: __nctl_svc_do_status_post <svc_name> <var_name> ...
__nctl_svc_do_status_post()
{
	local svc_name="$1"
	local var_name="$2"
	shift 2

	nctl_svc_do_is_failed && return

	return 0
}
declare -fr __nctl_svc_do_status_post

# Call default (inherit)
: ${nctl_svc_do_status_post:='__nctl_svc_do_status_post'}

# Usage: __nctl_svc_do_status_daemon <svc_name> <var_name> ...
__nctl_svc_do_status_daemon()
{
	local svc_name="$1"
	local var_name="$2"
	shift 2
	local -i rc=0

	nctl_svc_do_is_failed && return

	# Get status of the daemon
	nctl_arg_is_function "$nctl_svc_get_daemon_status" || return
	"$nctl_svc_get_daemon_status" "$svc_name" "$var_name" "$@" || nctl_inc_rc rc

	# Print status unless quiet
	if ! nctl_is_yes "$NCTL_SVC_QUIET"; then
		# Check bounds before accessing array: value must not be empty
		nctl_is_empty_var nctl_svc_daemon_status_msgs $rc &&
			rc=$nctl_svc_daemon_status_unknown

		printf '  %16s : %s\n' \
			"$svc_name" "${nctl_svc_daemon_status_msgs[$rc]}"
	fi

	return $rc
}
declare -fr __nctl_svc_do_status_daemon

# Call default (inherit)
: ${nctl_svc_do_status_daemon:='__nctl_svc_do_status_daemon'}

# Usage: __nctl_svc_do_status <svc_name> ...
__nctl_svc_do_status()
{
	local svc_name="$1"
	shift

	nctl_arg_is_function "$nctl_svc_do" || return

	"$nctl_svc_do" status "$svc_name" "$@"
}
declare -fr __nctl_svc_do_status

# Call default (inherit)
: ${nctl_svc_do_status:='__nctl_svc_do_status'}

# Usage: __nctl_svc_status <title> <svc_name1> <svc_name2> ...
__nctl_svc_status()
{
	local title="$1"
	shift

	# Implement custom message output subsystem, separated from SysV initscripts one
	nctl_is_yes "$NCTL_SVC_QUIET" || printf 'Status of %s services:\n' "$title"
	nctl_action_for_each "$nctl_svc_do_status" "$@"
}
declare -fr __nctl_svc_status

# Call default (inherit)
: ${nctl_svc_status:='__nctl_svc_status'}

#
# Usage
#

# Usage: __nctl_svc_usage
__nctl_svc_usage()
{
	local svc_list

	nctl_skip_spaces "$NCTL_SVC_LIST" svc_list
	nctl_strreplace "$svc_list" '/all' '' svc_list
	nctl_strreplace "$svc_list" '/+([[:space:]])' '|' svc_list
	svc_list="all|$svc_list"

	nctl_is_yes "$NCTL_SVC_QUIET" ||
	printf \
		"${NCTL_SVC_USAGE:-\$NCTL_SVC_USAGE is not specified in \"$program_invocation_name\"}\n" \
		"$program_invocation_short_name" \
		"$svc_list" >&2
	exit 1
}
declare -fr __nctl_svc_usage

: ${nctl_svc_usage:='__nctl_svc_usage'}

################################################################################
# Initialization                                                               #
################################################################################

## Parse/Adjust arguments

# Usage: nctl_svc_check_svc_list <svc_name1> <svc_name2> ...
nctl_svc_check_svc_list()
{
	local svc_name svc_list svc_unknown
	local -i rc=0

	if [ $# -le 1 ]; then
		if [ $# -eq 0 -o "$1" = 'all' ]; then
			[ -z "$NCTL_SVC_LIST" ] || nctl_skip_spaces "$NCTL_SVC_LIST"
			return
		fi
	fi
	svc_list=' '
	while [ $# -gt 0 ]; do
		if [ -z "$1" ]; then
			shift
			continue
		fi
		for svc_name in $NCTL_SVC_LIST ''; do
			if [ "$1" = "$svc_name" -a -n "${svc_list##*$svc_name *}" ]; then
				svc_list="$svc_list$svc_name "
				break
			fi
		done
		if [ -z "$svc_name" ]; then
			svc_unknown="$svc_unknown$1 "
			: $((rc++))
		fi
		shift
	done
	if [ -n "$svc_unknown" ]; then
		nctl_skip_spaces "$svc_unknown" svc_unknown
		nctl_is_yes "$NCTL_SVC_QUIET" ||
		printf '%s: %s: ignoring unknown/duplicated services:\n  %s\n' \
		"$program_invocation_short_name" "$FUNCNAME" "$svc_unknown" >&2
	fi

	nctl_skip_spaces "$svc_list" svc_list
	[ -n "$svc_list" ] && printf '%s' "$svc_list"
	return $rc
}
declare -fr nctl_svc_check_svc_list

# Suppress any messages/logging output
: ${NCTL_SVC_QUIET:=n}

# Source application-specific settings
if ! nctl_is_no "$NCTL_SVC_SYS_CONFIG"; then
	nctl_SourceIfNotEmpty "/etc/default/$NCTL_SVC_CONFIG" ||
	nctl_SourceIfNotEmpty "/etc/default/$(nctl_strtolower "${NCTL_SVC_NAME:-$program_invocation_short_name}")" ||
	nctl_SourceIfNotEmpty "/etc/default/$program_invocation_short_name"
fi

# Get action and services list
declare NCTL_SVC_ACTION="$1"
shift
set -- "$NCTL_SVC_ACTION" $(nctl_svc_check_svc_list "$@")
: ${NCTL_SVC_ACTION:=usage}
