# --- STAGE 1: Compilation Engine ---
FROM maven:3.9.6-eclipse-temurin-21-alpine AS compiler
WORKDIR /build

# Isolate pom.xml resolution to leverage caching layers
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy structural codebase artifacts and execute production package build
COPY src ./src
RUN mvn clean package -DskipTests

# --- STAGE 2: Lightweight JRE Linux Runtime Execution ---
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# Steal ONLY the compiled standalone portable JAR from the build stage
COPY --from=compiler /build/target/ingestion-service-1.0.0.jar gateway.jar

# Define network routing target vectors
EXPOSE 8081

# Boot application cleanly using standard JVM flags
ENTRYPOINT ["java", "-jar", "gateway.jar"]
