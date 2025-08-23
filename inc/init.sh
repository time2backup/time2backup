#
#  time2backup init variables and configuration default values
#
#  This file is part of time2backup (https://github.com/time2backup/time2backup)
#

#
#  Global variables declaration
#

backup_date_format="[1-9][0-9]{3}-[0-1][0-9]-[0-3][0-9]-[0-2][0-9][0-5][0-9][0-5][0-9]"
current_timestamp=$(date +%s)


#
#  Default core config
#

if [ "$lb_current_os" = Windows ] ; then
	enable_recurrent=false
	default_shutdown_cmd=(shutdown /s)
	preserve_permissions=false
else
	enable_recurrent=true
	default_shutdown_cmd=(shutdown -h now)
	preserve_permissions=true
fi


#
#  Default config
#

test_destination=true

keep_limit=-1
clean_old_backups=true
clean_keep=0

frequency=daily

mount=true

unmount_auto=true

keep_logs=on_error

notifications=true
email_report=none

hard_links=true
