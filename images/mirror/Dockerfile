FROM ghcr.io/regclient/regsync:v0.11.5 AS regsync

FROM alpine:3.22

RUN apk add --no-cache \
    aws-cli \
    ca-certificates \
    docker-credential-ecr-login \
    jq \
    kubectl

COPY --from=regsync /regsync /usr/local/bin/regsync

RUN adduser -D -u 65532 mirror

USER 65532:65532
WORKDIR /tmp

ENTRYPOINT ["/bin/sh"]
