# syntax=docker/dockerfile:1.7

FROM golang:1.25-bookworm AS build
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY main.go ./

ARG TARGETOS=linux
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags='-s -w' -o /out/backend-grpc ./main.go

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/backend-grpc /backend-grpc
EXPOSE 9000
ENTRYPOINT ["/backend-grpc"]
