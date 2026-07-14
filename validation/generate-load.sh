#!/bin/bash
#
# Generate load against Java 7 test service
# Usage: ./generate-load.sh <java-service-url> [duration-seconds] [requests-per-second]
#

set -e

# Configuration
SERVICE_URL="${1:-http://localhost:8080}"
DURATION="${2:-60}"  # Default: 60 seconds
RPS="${3:-10}"       # Default: 10 requests per second

if [ "$SERVICE_URL" = "-h" ] || [ "$SERVICE_URL" = "--help" ]; then
    echo "Usage: $0 <service-url> [duration-seconds] [requests-per-second]"
    echo ""
    echo "Examples:"
    echo "  $0 http://localhost:8080 60 10"
    echo "  $0 http://54.123.45.67:8080 120 20"
    echo ""
    exit 0
fi

echo "========================================="
echo "NewRelic Observe Proxy - Load Generator"
echo "========================================="
echo "Target: $SERVICE_URL"
echo "Duration: ${DURATION}s"
echo "Rate: ${RPS} req/s"
echo "========================================="
echo ""

# Calculate delay between requests (in milliseconds)
DELAY=$(awk "BEGIN {print 1000/$RPS}")

# Endpoints to test
ENDPOINTS=(
    "/api/users"
    "/api/orders/1"
    "/api/orders/2"
)

# Track metrics
TOTAL_REQUESTS=0
SUCCESSFUL_REQUESTS=0
FAILED_REQUESTS=0
START_TIME=$(date +%s)
END_TIME=$((START_TIME + DURATION))

echo "Starting load generation..."
echo ""

# Generate traffic
while [ $(date +%s) -lt $END_TIME ]; do
    # Pick random endpoint
    ENDPOINT=${ENDPOINTS[$RANDOM % ${#ENDPOINTS[@]}]}
    URL="${SERVICE_URL}${ENDPOINT}"
    
    # Make request
    RESPONSE=$(curl -s -w "\n%{http_code}" -o /dev/null "$URL" 2>&1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
    
    if [ "$HTTP_CODE" = "200" ]; then
        SUCCESSFUL_REQUESTS=$((SUCCESSFUL_REQUESTS + 1))
        echo "✓ Request #${TOTAL_REQUESTS}: ${ENDPOINT} → 200 OK"
    else
        FAILED_REQUESTS=$((FAILED_REQUESTS + 1))
        echo "✗ Request #${TOTAL_REQUESTS}: ${ENDPOINT} → ${HTTP_CODE} ERROR"
    fi
    
    # Sleep to maintain rate
    sleep $(awk "BEGIN {print $DELAY/1000}")
done

echo ""
echo "========================================="
echo "Load Generation Complete"
echo "========================================="
echo "Total Requests:      $TOTAL_REQUESTS"
echo "Successful (200):    $SUCCESSFUL_REQUESTS"
echo "Failed:              $FAILED_REQUESTS"
echo "Success Rate:        $(awk "BEGIN {print ($SUCCESSFUL_REQUESTS*100)/$TOTAL_REQUESTS}")%"
echo "Duration:            ${DURATION}s"
echo "Actual RPS:          $(awk "BEGIN {print $TOTAL_REQUESTS/$DURATION}")"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Check nginx logs for captured spans"
echo "2. Verify data in Observe"
echo "3. Run: ./check-nginx-logs.sh <nginx-ip>"
