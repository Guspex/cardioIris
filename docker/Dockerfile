FROM intersystems/irishealth-community:2026.1

USER root
RUN apt-get update && apt-get install -y git curl && rm -rf /var/lib/apt/lists/*

USER irisowner
WORKDIR /home/irisowner

COPY --chown=irisowner:irisowner src/ ./src/
COPY --chown=irisowner:irisowner data/ ./data/
COPY --chown=irisowner:irisowner dashboard/ ./dashboard/
COPY --chown=irisowner:irisowner tests/ ./tests/
COPY --chown=irisowner:irisowner docker/iris.conf /usr/irissys/iris.conf

EXPOSE 52773 1972

HEALTHCHECK --interval=30s --timeout=15s --start-period=60s --retries=5 \
  CMD iris qlist IRIS 2>/dev/null | grep -q "running" || exit 1
