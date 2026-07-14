# Use Java 8 base image (Amazon Corretto)
# Note: OpenJDK 7 images are no longer available on Docker Hub
# NewRelic Agent v6.5.0 supports both Java 7 and 8
FROM amazoncorretto:8

# Install Maven
RUN yum install -y maven && \
    yum clean all

# Install Tomcat 7
ENV CATALINA_HOME /usr/local/tomcat
ENV PATH $CATALINA_HOME/bin:$PATH
RUN mkdir -p "$CATALINA_HOME"
WORKDIR $CATALINA_HOME

# Download and install Tomcat 7.0.109
RUN curl -fSL "https://archive.apache.org/dist/tomcat/tomcat-7/v7.0.109/bin/apache-tomcat-7.0.109.tar.gz" -o tomcat.tar.gz && \
    tar -xvf tomcat.tar.gz --strip-components=1 && \
    rm bin/*.bat && \
    rm tomcat.tar.gz

# Copy application source
WORKDIR /app
COPY pom.xml ./
COPY src ./src

# Build the WAR file
RUN mvn clean package

# Deploy WAR to Tomcat
RUN cp target/java7-test-service.war $CATALINA_HOME/webapps/

# Copy NewRelic agent (Note: You'll need to download this separately)
# NewRelic Java Agent v6.5.0 - last version with Java 7 support
# IMPORTANT: Copy config BEFORE extracting zip to prevent overwrite
COPY newrelic/newrelic.yml /app/newrelic/newrelic.yml
COPY newrelic/newrelic.jar /app/newrelic/newrelic.jar

# Create logs directory
RUN mkdir -p /app/logs

# Expose Tomcat port
EXPOSE 8080

# Set NewRelic environment variables
ENV NEW_RELIC_APP_NAME="Java7-Test-Service"
ENV NEW_RELIC_LOG_FILE_NAME="newrelic_agent.log"

# Start Tomcat with NewRelic agent
CMD ["sh", "-c", "CATALINA_OPTS=\"-javaagent:/app/newrelic/newrelic.jar -Dnewrelic.config.file=/app/newrelic/newrelic.yml\" $CATALINA_HOME/bin/catalina.sh run"]
