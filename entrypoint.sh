#!/bin/sh

# If CRON is defined, set up cron daemon
if [ -n "$CRON" ]; then
    echo "========== CRON SCHEDULER INITIALIZED =========="
    echo "Cron schedule set to: $CRON"
    
    # Save environment variables to a file so they are available to the cron job
    env | grep -E '^MEDIA_ROOT|^FORCE|^PATH|^LANG' > /app/env.sh
    
    # Create the cron job in the Alpine root crontab
    echo "$CRON . /app/env.sh && pwsh -File /app/Sync-AbsToBookOrbit.ps1" > /var/spool/cron/crontabs/root
    
    # Run crond in the foreground
    echo "Starting cron daemon..."
    exec crond -f -l 2
else
    # One-shot mode: run the script once and exit
    echo "No CRON schedule specified. Running one-shot execution..."
    exec pwsh -File /app/Sync-AbsToBookOrbit.ps1
fi
