# Java 7 Test Service

Simple servlet application instrumented with NewRelic Agent v6.5.0 for testing proxy reconfiguration.

## Requirements

- Java 7 (JDK 1.7)
- Maven 3.x
- NewRelic Java Agent v6.5.0

## Getting NewRelic Agent v6.5.0

NewRelic agent v6.5.0 is the last version that supports Java 7. Download it:

```bash
# Download the agent
curl -L https://download.newrelic.com/newrelic/java-agent/newrelic-agent/6.5.0/newrelic-java-6.5.0.zip -o newrelic.zip

# Extract
unzip newrelic.zip

# Copy the jar to the newrelic directory
cp newrelic/newrelic.jar java-service/newrelic/

# Clean up
rm -rf newrelic newrelic.zip
```

## Building

```bash
cd java-service
mvn clean package
```

This creates `target/java7-test-service.war`.

## Running Locally (with Tomcat 7)

### Prerequisites
- Tomcat 7 installed and `CATALINA_HOME` set
- NewRelic jar in `newrelic/` directory

### Start
```bash
export NGINX_HOST=<nginx-ip-or-hostname>
./run.sh
```

The service will start on `http://localhost:8080/java7-test-service/`

## Running with Docker

```bash
# Build the image
docker build -t java7-test-service .

# Run the container
docker run -p 8080:8080 \
  -e NGINX_HOST=<nginx-ip> \
  java7-test-service
```

## Endpoints

### GET /api/users
Returns a list of mock users from in-memory H2 database.

**Example:**
```bash
curl http://localhost:8080/java7-test-service/api/users
```

**Response:**
```json
{
  "users": [
    {"id": 1, "name": "Alice", "email": "alice@example.com"},
    {"id": 2, "name": "Bob", "email": "bob@example.com"},
    {"id": 3, "name": "Charlie", "email": "charlie@example.com"}
  ]
}
```

**NewRelic Spans Generated:**
- 1 parent span (WebTransaction/Servlet/UsersServlet)
- 1 database query span (SELECT users)

### GET /api/orders/{userId}
Returns orders for a specific user.

**Example:**
```bash
curl http://localhost:8080/java7-test-service/api/orders/1
```

**Response:**
```json
{
  "orders": [
    {"id": 1, "product": "Widget A", "amount": 29.99},
    {"id": 2, "product": "Widget B", "amount": 49.99}
  ]
}
```

**NewRelic Spans Generated:**
- 1 parent span (WebTransaction/Servlet/OrdersServlet)
- 2 database query spans (SELECT orders, SELECT user)

## NewRelic Configuration

The agent is configured in `newrelic/newrelic.yml` to:
- Use a dummy license key (not validated)
- Point to custom nginx endpoint via `$NGINX_HOST` environment variable
- Enable distributed tracing
- Enable span events
- Log to `logs/newrelic_agent.log`

## Verifying Agent Connection

Check the NewRelic agent logs:

```bash
tail -f logs/newrelic_agent.log
```

You should see:
```
INFO: New Relic Agent: Java Agent v6.5.0 is starting up
INFO: Environment: development
INFO: Agent is reporting to: https://<nginx-host>:443
```

## Troubleshooting

### Agent fails to connect
- Verify `NGINX_HOST` environment variable is set correctly
- Check nginx is listening on port 443
- Verify SSL certificate is trusted by Java 7 keystore

### No spans are generated
- Check agent logs for errors
- Verify endpoints are being called (`curl` the API)
- Confirm span_events.enabled = true in newrelic.yml

### Build fails
- Ensure Java 7 is installed: `java -version`
- Ensure Maven is using Java 7: `mvn -version`
