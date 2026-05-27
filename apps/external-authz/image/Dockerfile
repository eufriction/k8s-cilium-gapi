# syntax=docker/dockerfile:1.7

FROM golang:1.23-bookworm AS build
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

ARG TARGETOS=linux
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags='-s -w' -o /out/external-authz .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/external-authz /external-authz
EXPOSE 8080 9000
ENTRYPOINT ["/external-authz"]
