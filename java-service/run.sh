#!/bin/bash
#
# Start Tomcat with NewRelic Agent
#

# Check if NewRelic jar exists
if [ ! -f "newrelic/newrelic.jar" ]; then
    echo "ERROR: newrelic.jar not found!"
    echo "Download NewRelic Java Agent v6.5.0 from:"
    echo "https://download.newrelic.com/newrelic/java-agent/newrelic-agent/6.5.0/newrelic-java-6.5.0.zip"
    echo ""
    echo "Extract and place newrelic.jar in the newrelic/ directory"
    exit 1
fi

# Set NewRelic host (nginx endpoint)
export NGINX_HOST="${NGINX_HOST:-localhost}"
echo "NewRelic agent will connect to: $NGINX_HOST:443"

# Set Java options
export CATALINA_OPTS="-javaagent:$(pwd)/newrelic/newrelic.jar \
    -Dnewrelic.config.file=$(pwd)/newrelic/newrelic.yml \
    -Dnewrelic.environment=development"

# Start Tomcat
echo "Starting Tomcat 7 with NewRelic agent..."
$CATALINA_HOME/bin/catalina.sh run
