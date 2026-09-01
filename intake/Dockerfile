# A static binary in a scratch image. Nothing to patch, nothing to shell into,
# nothing to run but the one process — which is what a service meant to sit
# unattended for years should be.
FROM golang:1.26-alpine AS build

WORKDIR /src

# Dependencies first, so a code change does not re-resolve them.
COPY go.mod go.sum ./
RUN go mod download

COPY *.go ./
# Static, stripped, and reproducible enough that two builds of one commit match.
RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath -ldflags="-s -w" -o /intake .

FROM scratch

# The CA bundle, because the only two things this talks to are object storage
# and an SMTP relay, and both are TLS. A scratch image has no roots at all and
# the failure is a certificate error at the moment somebody presses send.
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /intake /intake

# Not root, and no home to write to. This process reads a request and writes to
# somebody else's bucket; it has no business with a filesystem.
USER 65534:65534

EXPOSE 8080
ENTRYPOINT ["/intake"]
