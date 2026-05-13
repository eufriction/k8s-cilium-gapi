# syntax=docker/dockerfile:1.7

FROM golang:1.23-bookworm AS build
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

ARG TARGETOS=linux
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags='-s -w' -o /out/coraza-waf-extproc .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/coraza-waf-extproc /coraza-waf-extproc
COPY rules.conf /etc/coraza/rules.conf
EXPOSE 4317
ENTRYPOINT ["/coraza-waf-extproc"]
