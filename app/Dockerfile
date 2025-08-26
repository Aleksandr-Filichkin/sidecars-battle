FROM eclipse-temurin:21-jre-jammy

ENV APP_HOME=/app \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75 -Djava.security.egd=file:/dev/./urandom"

WORKDIR ${APP_HOME}

COPY target/echo-0.0.1-SNAPSHOT.jar app.jar

EXPOSE 8080

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]


