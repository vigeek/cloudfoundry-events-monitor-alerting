# cloudfoundry-events-monitor-alert
Monitors cloud foundry events API for application failures, alerts to PagerDuty (and others coming soon)

# Current limitatinos
1. Theres no mechanism to login in the script currently, assumes connectivity to your cloudfoundry endpoint.
2. Can only output to PagerDuty (slack coming shortly)

# Usage
1. Download the script and edit required variables (most importantly: PAGER_DUTY_API_KEY)
2. Execute script in a screen/background and let it run.
