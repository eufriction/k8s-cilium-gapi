package main

import (
	"context"
	"errors"
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/health"
	grpc_health_v1 "google.golang.org/grpc/health/grpc_health_v1"
	testpb "google.golang.org/grpc/interop/grpc_testing"
	"google.golang.org/grpc/reflection"
	"google.golang.org/grpc/status"
)

type testService struct {
	testpb.UnimplementedTestServiceServer
	hostname string
	serverID string
}

func newTestService() *testService {
	hostname, err := os.Hostname()
	if err != nil || hostname == "" {
		hostname = "backend-grpc"
	}

	serverID := os.Getenv("INSTANCE_ID")
	if serverID == "" {
		serverID = hostname
	}

	return &testService{
		hostname: hostname,
		serverID: serverID,
	}
}

func (s *testService) EmptyCall(context.Context, *testpb.Empty) (*testpb.Empty, error) {
	return &testpb.Empty{}, nil
}

func (s *testService) UnaryCall(_ context.Context, req *testpb.SimpleRequest) (*testpb.SimpleResponse, error) {
	if err := echoStatus(req.GetResponseStatus()); err != nil {
		return nil, err
	}

	return s.newSimpleResponse(req), nil
}

func (s *testService) CacheableUnaryCall(ctx context.Context, req *testpb.SimpleRequest) (*testpb.SimpleResponse, error) {
	return s.UnaryCall(ctx, req)
}

func (s *testService) StreamingOutputCall(
	req *testpb.StreamingOutputCallRequest,
	stream testpb.TestService_StreamingOutputCallServer,
) error {
	if err := echoStatus(req.GetResponseStatus()); err != nil {
		return err
	}

	params := req.GetResponseParameters()
	if len(params) == 0 {
		params = []*testpb.ResponseParameters{{Size: int32(payloadSize(req.GetPayload(), 64))}}
	}

	for _, param := range params {
		if interval := param.GetIntervalUs(); interval > 0 {
			time.Sleep(time.Duration(interval) * time.Microsecond)
		}

		resp := &testpb.StreamingOutputCallResponse{
			Payload: buildPayload(req.GetResponseType(), int(param.GetSize()), req.GetPayload()),
		}

		if err := stream.Send(resp); err != nil {
			return err
		}
	}

	return nil
}

func (s *testService) StreamingInputCall(stream testpb.TestService_StreamingInputCallServer) error {
	var total int32

	for {
		req, err := stream.Recv()
		if errors.Is(err, io.EOF) {
			return stream.SendAndClose(&testpb.StreamingInputCallResponse{
				AggregatedPayloadSize: total,
			})
		}
		if err != nil {
			return err
		}

		total += int32(len(req.GetPayload().GetBody()))
	}
}

func (s *testService) newSimpleResponse(req *testpb.SimpleRequest) *testpb.SimpleResponse {
	resp := &testpb.SimpleResponse{
		Payload:  buildPayload(req.GetResponseType(), int(req.GetResponseSize()), req.GetPayload()),
		Hostname: s.hostname,
	}

	if req.GetFillServerId() {
		resp.ServerId = s.serverID
	}
	if req.GetFillGrpclbRouteType() {
		resp.GrpclbRouteType = testpb.GrpclbRouteType_GRPCLB_ROUTE_TYPE_BACKEND
	}

	return resp
}

func buildPayload(respType testpb.PayloadType, size int, input *testpb.Payload) *testpb.Payload {
	if size <= 0 {
		size = payloadSize(input, 64)
	}

	source := input.GetBody()
	if len(source) == 0 {
		source = []byte("backend-grpc")
	}

	body := repeatToSize(source, size)
	if respType == 0 {
		respType = testpb.PayloadType_COMPRESSABLE
	}

	return &testpb.Payload{
		Type: respType,
		Body: body,
	}
}

func payloadSize(input *testpb.Payload, fallback int) int {
	if n := len(input.GetBody()); n > 0 {
		return n
	}
	return fallback
}

func repeatToSize(source []byte, size int) []byte {
	if size <= 0 {
		return nil
	}

	builder := strings.Builder{}
	builder.Grow(size)
	for builder.Len() < size {
		remaining := size - builder.Len()
		if remaining >= len(source) {
			builder.Write(source)
			continue
		}
		builder.Write(source[:remaining])
	}

	return []byte(builder.String())
}

func echoStatus(st *testpb.EchoStatus) error {
	if st == nil {
		return nil
	}
	if st.GetCode() == 0 && st.GetMessage() == "" {
		return nil
	}
	return status.Error(codes.Code(st.GetCode()), st.GetMessage())
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "9000"
	}

	listener, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Fatalf("listen on :%s: %v", port, err)
	}

	server := grpc.NewServer()
	healthServer := health.NewServer()
	healthServer.SetServingStatus("", grpc_health_v1.HealthCheckResponse_SERVING)

	grpc_health_v1.RegisterHealthServer(server, healthServer)
	testpb.RegisterTestServiceServer(server, newTestService())
	reflection.Register(server)

	errCh := make(chan error, 1)
	go func() {
		log.Printf("backend-grpc listening on %s", listener.Addr())
		errCh <- server.Serve(listener)
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	select {
	case sig := <-sigCh:
		log.Printf("shutting down backend-grpc after %s", sig)
		server.GracefulStop()
	case err := <-errCh:
		if err != nil {
			log.Fatalf("serve gRPC: %v", err)
		}
	}
}
