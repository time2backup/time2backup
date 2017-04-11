#!/bin/bash

########################################################
#                                                      #
#  time2backup                                         #
#  It's time to backup your files!                     #
#                                                      #
#  Website: https://github.com/pruje/time2backup       #
#  MIT License                                         #
#  Copyright (c) 2017 Jean Prunneaux                   #
#                                                      #
#  Version 1.0.0-rc.4 (2017-03-21)                     #
#                                                      #
########################################################


###########################
#  VARIABLES DECLARATION  #
###########################

version="1.0.0-rc.4"

portable_mode=false
user=""
sources=()
backup_destination=""
mounted=false
rsync_cmd=()
success=()
warnings=()
errors=()
report_details=""
default_verbose_level="INFO"
default_log_level="INFO"
backup_lock=""
force_unmount=false
force_shutdown=false


############################
#  DEFAULT CONFIG OPTIONS  #
############################

destination_subdirectories=true

consolemode=false
debugmode=false

mount=true
backup_disk_uuid=""

network_compression=false
ssh_options="ssh"

recurrent=false
frequency="daily"

keep_limit=-1
clean_old_backups=true
clean_keep=0

logs_save=false
keep_logs_if_error=true
log_level="$default_log_level"

notifications=true
email_report=false
email_report_if_error=false

exec_before_block=false
exec_after_block=false

# unmount after backup
unmount=false
unmount_auto=true

# shutdown after backup
shutdown=false
shutdown_cmd=(shutdown -h now)

# advanced options
hard_links=true
force_hard_links=false
mirror_mode=false
rsync_path=""
rsync_options=()
cmd_alias="/usr/bin/time2backup"
verbose_level="$default_verbose_level"


####################
#  INITIALIZATION  #
####################

# get real path of the script
if [ "$(uname)" == "Darwin" ] ; then
	# macOS which does not support readlink -f option
	current_script="$(perl -e 'use Cwd "abs_path";print abs_path(shift)' "$0")"
else
	current_script="$(readlink -f "$0")"
fi

# get directory of the current script
script_directory="$(dirname "$current_script")"

# load libbash
source "$script_directory/libbash/libbash.sh" > /dev/null
if [ $? != 0 ] ; then
	echo >&2 "Error: cannot load libbash. Please add it to the '$script_directory/libbash' directory."
	exit 1
fi

# load libbash GUI
source "$script_directory/libbash/libbash_gui.sh" > /dev/null
if [ $? != 0 ] ; then
	echo >&2 "Error: cannot load libbash GUI. Please add it to the '$script_directory/libbash' directory."
	exit 1
fi

# load default messages
source "$script_directory/locales/en.sh" > /dev/null
if [ $? != 0 ] ; then
	lb_error "Error: cannot load messages!"
	exit 1
fi

# get user language
lang="${LANG:0:2}"

# load translations (without errors)
case "$lang" in
	fr)
		source "$script_directory/libbash/locales/$lang.sh" &> /dev/null
		source "$script_directory/locales/$lang.sh" &> /dev/null
		;;
esac

# change current script name
lb_current_script_name="time2backup"


###############
#  FUNCTIONS  #
###############

# load functions
source "$script_directory/inc/functions.sh" > /dev/null
if [ $? != 0 ] ; then
	lb_error "Error: cannot load functions!"
	exit 1
fi


#######################
#  COMMAND FUNCTIONS  #
#######################

# load commands
source "$script_directory/inc/commands.sh" > /dev/null
if [ $? != 0 ] ; then
	lb_error "Error: cannot load tools!"
	exit 1
fi


##################
#  MAIN PROGRAM  #
##################

# get global options
while true ; do
	case "$1" in
		-C|--console)
			consolemode=true
			shift
			;;
		-c|--config)
			if [ -z "$2" ] ; then
				print_help
				exit 1
			fi
			config_file="$2"
			# test if file exists
			if ! [ -f "$config_file" ] ; then
				lb_error "Configuration file $config_file does not exists!"
				exit 1
			fi
			shift 2
			;;
		-p|--portable)
			portable_mode=true
			shift
			;;
		-u|--user)
			if [ -z "$2" ] ; then
				print_help
				exit 1
			fi
			user="$2"
			shift 2
			;;
		-l|--log-level)
			if [ -z "$2" ] ; then
				print_help
				exit 1
			fi
			log_level="$2"
			shift 2
			;;
		-v|--verbose-level)
			if [ -z "$2" ] ; then
				print_help
				exit 1
			fi
			verbose_level="$2"
			shift 2
			;;
		-D|--debug)
			debugmode=true
			shift
			;;
		-V|--version)
			echo $version
			exit
			;;
		-h|--help)
			print_help
			exit
			;;
		-*)
			print_help
			exit 1
			;;
		*)
			break
			;;
	esac
done

# if user not set, get current user
if [ -z "$user" ] ; then
	user="$(whoami)"
fi

# disable dialogs if console mode
if $consolemode ; then
	lbg_set_gui console
else
	# try to find display (if into a cron job on Linux)
	if [ "$lb_current_os" == "Linux" ] ; then

		u="$user"

		for i in 1 2 ; do
			# find user X display
			xdisplay=$(who | grep "^$u .*(:[0-9])$" | head -1 | sed "s/.*(\(:[0-9]*\))$/\1/g")

			# if found,
			if [ -n "$xdisplay" ] ; then
				# export the X display variable
				export DISPLAY="$xdisplay"

				# reset GUI tools
				lbg_set_gui
				break
			fi

			# if failed, try with the current user
			u="$(whoami)"
		done
	fi
fi

# test if rsync command is available
if ! lb_command_exists rsync ; then
	lbg_display_critical "$tr_error_no_rsync_1\n$tr_error_no_rsync_2"
	exit 1
fi

# set default configuration file and path
if [ -z "$config_file" ] ; then

	if $portable_mode ; then
		config_directory="$script_directory/config/"
	else
		config_directory="$(lb_homepath $user)/.config/time2backup/"
		if [ $? != 0 ] ; then
			lbg_display_error "$tr_error_getting_homepath_1\n$tr_error_getting_homepath_2"
			exit 3
		fi
	fi

	config_file="$config_directory/time2backup.conf"
else
	# parent directory of specified configuration file
	config_directory="$(dirname "$config_file")"
fi

# default config files
config_sources="$config_directory/sources.conf"
config_excludes="$config_directory/excludes.conf"
config_includes="$config_directory/includes.conf"

# defines log level
if ! $debugmode ; then
	# if not set (unknown error), set to default level
	if ! lb_set_loglevel "$log_level" ; then
		lb_set_loglevel "$default_log_level"
	fi

	# defines verbose level
	# if not set (unknown error), set to default level
	if ! lb_set_loglevel "$verbose_level" ; then
		lb_set_loglevel "$default_verbose_level"
	fi
fi

lb_display_debug "Running in DEBUG mode...\n"
lb_display_debug "Config file: $config_file"

# config initialization
if ! create_config ; then
	lbg_display_error "$tr_error_create_config"
	exit 3
fi

# load configuration; don't care of errors
load_config &> /dev/null

# if configuration is not set (destination empty),
# run first wizard and exit
if [ -z "$destination" ] ; then
	first_run
	exit $?
fi

mode="$1"
shift

# command operations
case "$mode" in
	backup|history|restore|config|install|uninstall)
		t2b_$mode $*
		;;
	"")
		# display choose operation dialog
		choose_operation
		;;
	*)
		print_help
		exit 1
		;;
esac

lb_exitcode=$?

if $debugmode ; then
	echo
	lb_display_debug "Exited with code: $lb_exitcode"
fi

lb_exit
