#!/bin/bash

[ -z "$__included_libfile_sh" ] || return 0
declare -r __included_libfile_sh=1

# External tool dependencies, MUST always be defined,
# even if empty (e.g.: declare -a crt1_request_tools_list=())
declare -a crt1_request_tools_list=(
	'rm'		# rm(1)
	'mv'		# mv(1)
	'install'	# install(1)
	'chown'		# chown(1)
	'chmod'		# chmod(1)
	'inotifywait'	# inotifywait(1)
)

# Source startup code
. /netctl/lib/bash/crt1.sh

# Source functions libraries
. /netctl/lib/bash/libbool.sh
. /netctl/lib/bash/librtti.sh
. /netctl/lib/bash/libiter.sh
. /netctl/lib/bash/libstring.sh

# Standart stream file descriptors
declare -ir NCTL_STDIN=0 NCTL_STDOUT=1 NCTL_STDERR=2

# First and last valid file descriptor number
declare -ir NCTL_FIRST_FD=0 NCTL_LAST_FD=0x7fffffff

# Usage: nctl_is_valid_fd <fd>
nctl_is_valid_fd()
{
	local -i fd="${1:?missing 1st argument to function \"$FUNCNAME\" (fd)}"

	[ $fd -ge $NCTL_FIRST_FD -a $fd -le $NCTL_LAST_FD ]
}
declare -fr nctl_is_valid_fd

# First file descriptor number, available for automatic selection in nctl_openfile()
nctl_is_valid_fd ${NCTL_OPENFILE_START_FD:=256} || NCTL_OPENFILE_START_FD=256
declare -ir NCTL_OPENFILE_START_FD
# Next, possibly unused, file descriptor
declare -i NCTL_OPENFILE_NEXT_FD=$NCTL_OPENFILE_START_FD

# Usage: nctl_openfile <pathname> <mode> [<perm>] [<var>]
nctl_openfile()
{
	trap '
		trap - RETURN
		[ $rc -eq 0 ] || nctl_openfile_fd=-1
		nctl_return "$nctl_openfile_var" "$nctl_openfile_fd"
	' RETURN
	local nctl_openfile_pathname="${1:?missing 1st argument to function \"$FUNCNAME\" (pathname)}"
	local nctl_openfile_mode="${2:?missing 2d argument to function \"$FUNCNAME\" (mode)}"
	local nctl_openfile_perm="$3"
	local nctl_openfile_var="$4"
	local -i i nctl_openfile_fd rc=0
	local __shopt
	# Check mode value
	case "$nctl_openfile_mode" in
		'<')
			# Read
			nctl_openfile_perm=''
			;;
		'>')
			# Write
			;;
		'>>')
			# Append
			;;
		'<>')
			# Read/Write
			;;
		*)
			printf '%s: invalid file open mode: %s\n' \
				"$FUNCNAME" "$nctl_openfile_mode" >&2
			! : || nctl_inc_rc rc || return $rc
	esac
	# Find next free file descriptor number
	for ((i = NCTL_OPENFILE_NEXT_FD; i <= NCTL_LAST_FD; i++)); do
		if [ ! -e "$NCTL_PROC_DIR/self/fd/$i" ]; then
			nctl_openfile_fd=$i
			break
		fi
	done
	nctl_is_valid_fd $nctl_openfile_fd || nctl_inc_rc rc || return $rc
	# Opening...
	__shopt=`shopt -p execfail`
	shopt -s execfail
	{
		trap ':' ERR
		eval "exec $nctl_openfile_fd$nctl_openfile_mode$nctl_openfile_pathname"
		nctl_inc_rc rc
		trap - ERR
	} 2>/dev/null
	eval "$__shopt"
	[ $rc -eq 0 ] || return $rc
	# Update permissions if neccessary
	if [ -n "$nctl_openfile_perm" ]; then
		chmod "$nctl_openfile_perm" "$nctl_openfile_pathname"
		if ! nctl_inc_rc rc; then
			nctl_closefile $nctl_openfile_fd
			rm -f "$nctl_openfile_pathname"
		fi
	fi
	# Save next, possibly empty, file descriptor number
	NCTL_OPENFILE_NEXT_FD=$((nctl_openfile_fd + 1))
	[ $NCTL_OPENFILE_NEXT_FD -gt $NCTL_LAST_FD ] &&
		NCTL_OPENFILE_NEXT_FD=$NCTL_OPENFILE_START_FD

	return $rc
}
declare -fr nctl_openfile

# Usage: nctl_closefile <fd>
nctl_closefile()
{
	local -i fd="${1:?missing 1st argument to function \"$FUNCNAME\" (fd)}"
	# Invalid fd value?
	nctl_is_valid_fd $fd || return
	# Already closed?
	[ ! -e "$NCTL_PROC_DIR/self/fd/$fd" ] && return
	# Closing...
	eval "exec $fd<&-"
	# Closed?
	[ ! -e "$NCTL_PROC_DIR/self/fd/$fd" ]
}
declare -fr nctl_closefile

# Usage: nctl_waitfile file [<timeout>]
# Return: 0 - on success
nctl_waitfile()
{
	local f="${1:?missing 1st argument to funcion \"$FUNCNAME\" (file)}"

	local -i t="${2:-10}"
	local -i i __scale_factor=10
	local r

	[ $t -ge $__scale_factor ] || return
	i=$((t / __scale_factor))
	t=$((t / i))
	while [ $i -gt 0 -a ! -e "$f" ]; do
		r="$(inotifywait --timeout $t --event modify --format '<%f>' "${f%/*}" 2>&1)"
		case $? in
			0)
				# Found: if not what we expect try again
				# with no iter decrement
				[[ "$r" =~ \<${f##*/}\> ]] && break
				;;
			2)
				# Timeout: decrement iter
				: $((i--))
				;;
			*)
				# Some error: may be ${f%/*} was gone
				i=0
				break
		esac
	done
	[ $i -gt 0 -o -e "$f" ]
}
declare -fr nctl_waitfile

# Usage: nctl_SourceIfExists <file_to_source>
# Example: nctl_SourceIfExists /etc/
nctl_SourceIfExists()
{
	local f="$1"
	shift
	[ -f "$f" ] && . "$f" "$@"
}
declare -fr nctl_SourceIfExists

# Usage: nctl_SourceIfExecutable <file_to_source> [<arg1> <arg2> ...]
# Example: nctl_SourceIfExecutable /etc/rc.local
nctl_SourceIfExecutable()
{
	local f="$1"
	shift
	[ -f "$f" -a -x "$f" ] && . "$f" "$@"
}
declare -fr nctl_SourceIfExecutable

# Usage: nctl_SourceIfNotEmpty <file_to_source> [<arg1> <arg2> ...]
# Example: nctl_SourceIfNotEmpty /etc/default/rcS
nctl_SourceIfNotEmpty()
{
	local f="$1"
	shift
	[ -f "$f" -a -s "$f" ] && . "$f" "$@"
}
declare -fr nctl_SourceIfNotEmpty

# Usage: nctl_ExecIfExecutable <file_to_exec> [<arg1> <arg2> ...]
# Example: nctl_ExecIfExecutable '/bin/uname' -m
nctl_ExecIfExecutable()
{
	local f="$1"
	shift
	[ -f "$f" -a -x "$f" ] && "$f" "$@"
}
declare -fr nctl_ExecIfExecutable

# Usage: nctl_absolute <name> [<var>]
# Result: absolute path if <name> is in $PATH
nctl_absolute()
{
	local na_n="${1:?missing 1st argument to function \"$FUNCNAME\" (name_of_file)}"
	local na_s
	local na_var="$2"

	na_s="$na_n"
	na_n="${na_n##*/}"
	if [ -e "$na_s" -a ! -e "./$na_n" ]; then
		{
			hash -t "$na_s" || hash -p "$na_s" "$na_n"
		} &>/dev/null
		nctl_return "$na_var" "$na_s"
	fi

	# Store result of lookup into hashtable for speed any
	# later tool lookup with @this function and reference to <name>
	# without absolute path.
	#
	# NOTE:
	#   As subshell used for lookup it inherits parents copy of hashtable
	#   but scope of any modifications to hashtable is limited to this
	#   subshell only.
	#   To update current hashtable we call "hash -p ..." to associate <name>
	#   with its absolute path.
	na_s="$(
		{
			if ! hash -t "$na_n"; then
				hash "$na_n" &&
				hash -t "$na_n"
			fi
		} 2>/dev/null
	)" && [ -n "$na_s" ] &&
	hash -p "$na_s" "$na_n"

	nctl_return "$na_var" "$na_s"
}
declare -fr nctl_absolute

# Backup file permissions and ownership
: ${NCTL_INSTALL_MODE:='0644'}

# Usage: nctl_install <options to install(1)>
nctl_install()
{
	local opts="${*:?missing arguments to \"$FUNCNAME\". See install(1) for supported args.}"

	nctl_strreplace \
		" $opts" \
		'/+([[:space:]])@(-[mog]*([[:space:]])|--@(mode|owner|group)=)+([^[:space:]])' \
		'' \
		opts

	install \
		${NCTL_INSTALL_MODE:+-m"$NCTL_INSTALL_MODE"} \
		${NCTL_INSTALL_USER:+-o"$NCTL_INSTALL_USER"} \
		${NCTL_INSTALL_GROUP:+-g"$NCTL_INSTALL_GROUP"} \
		$opts
}
declare -fr nctl_install

# Backup file extension (to prevent conflicts with manual backups)
: ${NCTL_BAK:='.nbak'}

# Usage: nctl_backup <file1_pattern> [<file2_pattern> ...]
nctl_backup()
{
	nctl_backup__file()
	{
		[ ! -f "$1" ] || nctl_install "$1"{,"$NCTL_BAK"}
	}
	local -a a
	local -i rc=0

	nctl_paths_expand_a a "$@" || nctl_inc_rc rc || return $rc

	nctl_action_for_each nctl_backup__file "${a[@]}" || nctl_inc_rc rc

	# Remove internal function from global namespace
	unset -f nctl_backup__file

	return $rc
}
declare -fr nctl_backup

# Usage: nctl_restore <file1_pattern> [<file2_pattern> ...]
nctl_restore()
{
	nctl_restore__file()
	{
		rm -f "$1"
		mv -f "$1"{"$NCTL_BAK",}
	}
	local -a a
	local -i rc=0

	nctl_paths_expand_a a "$@" || nctl_inc_rc rc || return $rc

	nctl_action_for_each nctl_restore__file "${a[@]}" || nctl_inc_rc rc

	# Remove internal function from global namespace
	unset -f nctl_restore__file

	return $rc
}
declare -fr nctl_restore

# Usage: nctl_cleanup <file1_pattern> [<file2_pattern> ...]
nctl_cleanup()
{
	nctl_remove__file()
	{
		rm -f "$1$NCTL_BAK"
	}
	local -a a
	local -i rc=0

	nctl_paths_expand_a a "$@" || nctl_inc_rc rc || return $rc

	nctl_action_for_each nctl_remove__file "${a[@]}" || nctl_inc_rc rc

	# Remove internal function from global namespace
	unset -f nctl_remove__file

	return $rc
}
declare -fr nctl_cleanup

: ${NCTL_READ_TIMEOUT:=10}

# Usage: __nctl_action_fentry <entry>
__nctl_action_fentry()
{
	return 0
}
declare -fr __nctl_action_fentry

# Call default (inherit)
: ${nctl_action_fentry:='__nctl_action_fentry'}

# Usage: nctl_for_each_fentry_iterate <entry>
nctl_for_each_fentry_iterate()
{
	# Always success: called internally by nctl_for_each_fentry()
	local nctl_fefi_f="$1"
	local nctl_fefi_entry
	local -i nctl_fefi_lineno=${nctl_fefi_lineno:-0}
	local -ri nctl_fefi_maxlines=${nctl_fefi_maxlines:--1}
	local -i nctl_fefi_rc=0

	# 1. Ignore if maxlines already reached
	# 2. Ignore empty entries
	# 3. Ignore directories
	[ -z "$nctl_fefi_f" -o \
	  -d "$nctl_fefi_f" -o \
	  \( $nctl_fefi_maxlines -ge 0 -a \
	     $nctl_fefi_lineno -ge $nctl_fefi_maxlines \) \
	] && return $nctl_fefi_rc

	# Open file
	local -i nctl_fefi_fd

	nctl_openfile "$nctl_fefi_f" '<' '' nctl_fefi_fd ||
		nctl_inc_rc nctl_fefi_rc || return $nctl_fefi_rc

	# Read from file
	while read -u $nctl_fefi_fd -t "$NCTL_READ_TIMEOUT" nctl_fefi_entry; do
		# Execute action
		"$nctl_action_fentry" "$nctl_fefi_entry" ||
			nctl_inc_rc nctl_fefi_rc || continue
		# Count/limit number of lines to read
		[ $nctl_fefi_maxlines -ge 0 ] || continue
		[ $((++nctl_fefi_lineno)) -lt $nctl_fefi_maxlines ] || break
	done

	# Close file
	nctl_closefile $nctl_fefi_fd || nctl_inc_rc nctl_fefi_rc

	return $nctl_fefi_rc
}
declare -fr nctl_for_each_fentry_iterate

# Usage: nctl_for_each_fentry <file1> [<file2>...]
nctl_for_each_fentry()
{
	nctl_arg_is_function "$nctl_action_fentry" || return

	nctl_action_for_each_with_set_globs nctl_for_each_fentry_iterate "$@"
}
declare -fr nctl_for_each_fentry

# Usage: __nctl_action_dentry <entry>
__nctl_action_dentry()
{
	return 0
}
declare -fr __nctl_action_dentry

# Call default (inherit)
: ${nctl_action_dentry:='__nctl_action_dentry'}

# Usage: nctl_for_each_dentry_iterate <entry>
nctl_for_each_dentry_iterate()
{
	# Always success: called internally by nctl_for_each_dentry()
	local nctl_fedi_entry="$1"
	local -i nctl_fedi_depth=${nctl_fedi_depth:-0}
	local -ri nctl_fedi_maxdepth=${nctl_fedi_maxdepth:--1}
	local -i nctl_fedi_rc=0

	# Ignore empty entries
	[ -z "$nctl_fedi_entry" ] && return

	# Execute action
	"$nctl_action_dentry" "$nctl_fedi_entry" || nctl_inc_rc nctl_fedi_rc

	# Recurse subdirs up to max depth
	if [ \( $nctl_fedi_maxdepth -lt 0 -o \
	        $nctl_fedi_depth -lt $nctl_fedi_maxdepth \) -a \
	    -d "$nctl_fedi_entry" ]; then
		nctl_fedi_depth=$((nctl_fedi_depth + 1)) \
			nctl_action_for_each_with_set_globs \
				"$FUNCNAME" \
				"$nctl_fedi_entry"/* ||
			nctl_inc_rc nctl_fedi_rc
	fi

	return $nctl_fedi_rc
}
declare -fr nctl_for_each_dentry_iterate

# Usage: nctl_for_each_dentry <dir_entry1> [<dir_entry2>...]
nctl_for_each_dentry()
{
	nctl_arg_is_function "$nctl_action_dentry" || return

	nctl_action_for_each_with_set_globs nctl_for_each_dentry_iterate "$@"
}
declare -fr nctl_for_each_dentry

# Usage: nctl_update_dentries <user> <group> <f_perm> <d_perm> <entry1> <entry2> ...
nctl_update_dentries()
{
	local user="$1" group="$2" f_perm="$3" d_perm="$4"
	shift 4
	local -i rc=0

	# Usage: nctl_update_dentries__nctl_action_dentry <entry>
	nctl_update_dentries__nctl_action_dentry()
	{
		local o

		# Owner/group
		[ -z "$user" ] || o="$user"
		[ -z "$group" ] || o="$o:$group"
		[ -z "$o" ] || chown -f "$o" "$1" &>/dev/null || return

		# Permissions
		[ -d "$1" ] && o="$d_perm" || o="$f_perm"
		[ -z "$o" ] || chmod -f "$o" "$1" &>/dev/null
	}

	nctl_action_dentry='nctl_update_dentries__nctl_action_dentry' \
		nctl_for_each_dentry "$@" || nctl_inc_rc rc

	# Remove internal function(s) from global namespace
	unset -f nctl_update_dentries__nctl_action_dentry

	return $rc
}
declare -fr nctl_update_dentries

################################################################################
# Initialization                                                               #
################################################################################

### Setup directories paths variables if needed

# Be sure to have set these vars
: ${NCTL_DEV_DIR:='/dev'} ${NCTL_PROC_DIR:='/proc'} ${NCTL_SYS_DIR:='/sys'}
