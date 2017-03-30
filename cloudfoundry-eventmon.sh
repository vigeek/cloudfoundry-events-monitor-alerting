#!/bin/bash

# Custom CF Event Monitor:  Russ Thompson August 2016
# Built to monitor CF events of a specific target.
# Note to self:  possibly move variables into separate file.

####################### PAGERDUTY VARIABLES #######################

PAGER_DUTY_API_KEY="asdf8b0db978f69b49789c75feasdf"

####################### MISCELLANEOUS VARIABLES #######################

# Store results here to process later.
TEMP_FILE="/tmp/event_monitor.tmp"

# How often in between checks (seconds)
SLEEP_INTERVAL="120"

####################### LOGGING VARIABLES #######################

# Enable logging?
LOG_ENABLED="1"

# Also log to syslog?
# If enabled, will also log events to syslog
LOG_SYSLOG="1"

# Standard LOG file Location
LOG_LOCATION="/var/log/cf-event-monitor.log"

# Adds DEBUG mode logging.
# This will only log to LOG_LOCATION, not syslog (it will be very verbose)
LOG_VERBOSE="0"
# Set a custom location for DEBUG output, leave blank and it will use LOG_LOCATION instead.
LOG_DEBUG_FILE="/var/log/cf-event-monitor.debug"

####################### CLOUD FOUNDRY CONSTANTS(INACTIVE) #######################

# Cloud Foundry Endpoint (leave later for possible authentication)
readonly CF_ENDPOINT="https://api.run.yourdomain.net"

# Define the CF target, we will monitor every space.
readonly CF_TARGET="your-cf-org"

# Authentication adding soon, as needed (TBD).
readonly CF_USER=""
readonly CF_PASSWORD=""

####################### MISCELLANEOUS CONSTANTS  #######################

# Set the name just for logging purposes
readonly BASE_NAME=$(basename -- "$0")
# Use pwd instead of dirname/basename here to account for execution out of scope.
readonly BASE_PATH="$(pwd)"

####################### CORE FUNCTIONS #######################

# Create a logging function with options from above.
function logit(){
  if [ -n "$1" ] ; then
    LOG_MESSAGE=$1
    if [ $LOG_ENABLED -eq "1" ] ; then
      echo -e "$(date) $(hostname -s) $BASE_NAME: $LOG_MESSAGE" | tee -a $LOG_LOCATION
      if [ $LOG_SYSLOG -eq "1" ] ; then
        logger -t $BASE_NAME "$LOG_MESSAGE"
      fi
    fi
  fi
}

# Target our desired organization
cf target -o $CF_TARGET 


# Set the description (FAILURE_MESSAGE) maximum length 1024.
set_pagerduty_message() {
  FAILURE_MESSAGE="Application: $THE_ACTOR | Exit Description: $THE_DESC | Timestamp: $THE_DATE | Space: $THE_GUID"
}

# Refresh the timestamp in cloud foundry format.
refresh_timestamp() {
  CHECK_POINT=$(date -u +%Y-%m-%d"T%T")
}

# Call the events API for app.crash events and filter by timestamp (in roughly two minute increments)
get_cf_results() {
  cf curl "/v2/events?q=timestamp>=$CHECK_POINT&q=type:app.crash" \
  | grep -e "actee_name" -e "timestamp" -e "exit_description" -e "space_guid" > $TEMP_FILE
}

# Send out an alert to PagerDuty when a failure is detected.
send_pagerduty(){
  logit "PagerDuty Message: $FAILURE_MESSAGE" 

  PD_INCIDENT_KEY="$THE_ACTOR"
  logit "Using PagerDuty incident_key: $PD_INCIDENT_KEY"
  logit "Calling PagerDuty API to send alert...."

  curl -H "Content-type: application/json" -X POST -d \
  "{ \"service_key\": \"$PAGER_DUTY_API_KEY\", \"event_type\": \"trigger\", \"incident_key\": \"$PD_INCIDENT_KEY\", \"description\": \"$FAILURE_MESSAGE\", \"details\": \"$FAILURE_MESSAGE\" }" \
  https://events.pagerduty.com/generic/2010-04-15/create_event.json
  if [ "$?" -eq "0" ] ; then
    logit "Successfully sent PagerDuty alert for application crash: $THE_ACTOR"
  else
    logit "Failed to send PagerDuty alert for application crash: $THE_ACTOR"
  fi
}

# Try and attempt to use the custom pager duty services, otherwise default to dev.
prepare_pagerduty() {
  # If we don't have a date from the event, use our date which is within range.
  if [ -z "$THE_DATE" ] ; then
    THE_DATE="$CHECK_POINT"
  fi  
  # We can assume that an application name is at least two characters.
  if [ "$(echo $THE_ACTOR | wc -c)" -gt 2 ] ; then
    logit "Detected application $THE_ACTOR has actually failed at $THE_DATE"
    # Only invoke the custom integration keys for production.
      set_pagerduty_message
      send_pagerduty
  fi
}

# Parse the temporary file to see if we've got a legit event.
# Make sure that the fields we need to create an alert aren't null.
initiate_pagerduty() {
  while true ; do
    read line1 || break
    THE_ACTOR=$(echo $line1 | awk '{print $2}' | tr -cd '[[:alnum:]]:_-')
    read line2 || break
    THE_DATE=$(echo $line2 | awk '{print $2}' | tr -cd '[[:alnum:]]:_-')
    read line3 || break
    THE_DESC=$(echo $line3 | awk '{for (i=2; i<NF; i++) printf $i " "; print $NF}' | tr -cd '[[:alnum:]] :_-')
    read line4 || break
    THE_GUID=$(echo $line4 | awk '{print $2}' | tr -cd '[[:alnum:]]:_-')
      if [ -n "$THE_ACTOR" ] && [ -n "$THE_DESC" ] && [ -n "$THE_DATE" ] ; then
        logit "Failure met field requirements, looks real, sending to function: prepare_pagerduty"
        prepare_pagerduty
      fi
  done < $TEMP_FILE
}

####################### CORE #######################

logit "Starting, preparing to monitor cloud foundry events...."

# In the event LOG_VERBOSE is enabled, enable bash DEBUG and redirect DEBUG output to our log file.
# Also maintain output to screen/stdout via tee.
if [ $LOG_VERBOSE -eq "1" ] ; then
  if [ -z "$LOG_DEBUG_FILE" ] ; then
    LOG_DEBUG_FILE=$LOG_LOCATION
  fi
  logit "LOG_VERBOSE enabled, all debug output going to $LOG_LOCATION"
  set -x
  exec &> >(tee -a "$LOG_DEBUG_FILE")
fi

# Create a initia timestamp (runs once)
refresh_timestamp

logit "Entering main event monitoring loop...."

while true ; do
  # Create separation between the timestamp and get_cf_results check
  sleep $SLEEP_INTERVAL
  # For increased verbosity on the intervals between checks.
  if [ $LOG_VERBOSE -eq "1" ] ; then
    logit "SEARCHING:  $CHECK_POINT TO $(date -u +%Y-%m-%d"T%T")"
  fi
  # Uses a base timestamp thats from 120 seconds ago, anything newer in the event log we'll get.
  get_cf_results
  # Get the current tiemstamp to use in query.
  refresh_timestamp
  if grep exit_description $TEMP_FILE ; then
    logit "Potential failure found, sending to function: initiate_pagerduty"
    initiate_pagerduty
  fi
done
