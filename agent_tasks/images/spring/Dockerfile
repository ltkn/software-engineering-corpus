# Spring Boot tasks: JDK 27, Maven, PostgreSQL 18, and every dependency the
# tasks use pre-fetched into ~/.m2 so builds run offline (--network none).
FROM eclipse-temurin:27-jdk
RUN apt-get update && apt-get install -y --no-install-recommends postgresql-18 \
    && rm -rf /var/lib/apt/lists/*
ARG MAVEN_VERSION=3.9.16
ADD https://repo1.maven.org/maven2/org/apache/maven/apache-maven/${MAVEN_VERSION}/apache-maven-${MAVEN_VERSION}-bin.tar.gz /tmp/maven.tgz
RUN tar -xzf /tmp/maven.tgz -C /opt && ln -s /opt/apache-maven-${MAVEN_VERSION}/bin/mvn /usr/local/bin/mvn && rm /tmp/maven.tgz
COPY pg-up /usr/local/bin/pg-up
COPY warmup /tmp/warmup
RUN chmod 755 /usr/local/bin/pg-up \
    && cd /tmp/warmup && pg-up && mvn -B -q dependency:go-offline verify \
    && runuser -u postgres -- /usr/lib/postgresql/18/bin/pg_ctl -D /var/lib/pg-tasks -w stop >/dev/null \
    && rm -rf /tmp/warmup /var/lib/pg-tasks
ENV MAVEN_OPTS="-Xmx384m"
WORKDIR /work
