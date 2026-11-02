// route-mutator-extproc is a minimal Envoy external processor that rewrites
// the `:path` pseudo-header and asks Envoy to clear the route cache.
//
// It exists to demonstrate what an ext_proc processor can do to routing when
// Envoy's `route_cache_action` is left at its default. A processor attached to
// one HTTPRoute rule can move a request onto a different rule, escaping the
// filters the original rule declared.
package main

import (
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"strings"
	"syscall"

	corev3 "github.com/envoyproxy/go-control-plane/envoy/config/core/v3"
	extprocv3 "github.com/envoyproxy/go-control-plane/envoy/service/ext_proc/v3"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type server struct {
	extprocv3.UnimplementedExternalProcessorServer
	from string
	to   string
}

func (s *server) Process(stream extprocv3.ExternalProcessor_ProcessServer) error {
	for {
		req, err := stream.Recv()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return status.Errorf(codes.Unknown, "recv: %v", err)
		}

		var resp *extprocv3.ProcessingResponse
		switch v := req.Request.(type) {
		case *extprocv3.ProcessingRequest_RequestHeaders:
			resp = s.handleRequestHeaders(v)

		case *extprocv3.ProcessingRequest_ResponseHeaders:
			resp = &extprocv3.ProcessingResponse{
				Response: &extprocv3.ProcessingResponse_ResponseHeaders{
					ResponseHeaders: &extprocv3.HeadersResponse{
						Response: &extprocv3.CommonResponse{},
					},
				},
			}

		default:
			// Bodies and trailers are acknowledged without changes.
			resp = &extprocv3.ProcessingResponse{
				Response: &extprocv3.ProcessingResponse_RequestBody{
					RequestBody: &extprocv3.BodyResponse{
						Response: &extprocv3.CommonResponse{},
					},
				},
			}
		}

		if err := stream.Send(resp); err != nil {
			return err
		}
	}
}

func (s *server) handleRequestHeaders(v *extprocv3.ProcessingRequest_RequestHeaders) *extprocv3.ProcessingResponse {
	path := ""
	for _, h := range v.RequestHeaders.GetHeaders().GetHeaders() {
		if h.GetKey() == ":path" {
			path = headerVal(h)
			break
		}
	}

	if !strings.HasPrefix(path, s.from) {
		return headersResponse(&extprocv3.CommonResponse{
			HeaderMutation: setHeaders(
				header("x-route-mutator", "pass"),
			),
		})
	}

	rewritten := s.to + strings.TrimPrefix(path, s.from)
	log.Printf("rewriting %s -> %s and clearing the route cache", path, rewritten)

	return headersResponse(&extprocv3.CommonResponse{
		// Envoy permits `:path` mutations unless the ext_proc filter sets
		// `mutation_rules.disallow_system`. Combined with clear_route_cache
		// this re-runs route matching against the rewritten path.
		HeaderMutation: setHeaders(
			overwrite(header(":path", rewritten)),
			header("x-route-mutator", "rewrote"),
		),
		ClearRouteCache: true,
	})
}

func headersResponse(common *extprocv3.CommonResponse) *extprocv3.ProcessingResponse {
	return &extprocv3.ProcessingResponse{
		Response: &extprocv3.ProcessingResponse_RequestHeaders{
			RequestHeaders: &extprocv3.HeadersResponse{Response: common},
		},
	}
}

func setHeaders(opts ...*corev3.HeaderValueOption) *extprocv3.HeaderMutation {
	return &extprocv3.HeaderMutation{SetHeaders: opts}
}

func header(key, value string) *corev3.HeaderValueOption {
	return &corev3.HeaderValueOption{
		Header: &corev3.HeaderValue{Key: key, RawValue: []byte(value)},
	}
}

func overwrite(opt *corev3.HeaderValueOption) *corev3.HeaderValueOption {
	opt.AppendAction = corev3.HeaderValueOption_OVERWRITE_IF_EXISTS_OR_ADD
	return opt
}

// headerVal returns the string value from a HeaderValue, preferring raw_value.
func headerVal(h *corev3.HeaderValue) string {
	if v := h.GetRawValue(); len(v) > 0 {
		return string(v)
	}
	return h.GetValue()
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "4317"
	}

	from := os.Getenv("REWRITE_FROM")
	if from == "" {
		from = "/anything/protected"
	}
	to := os.Getenv("REWRITE_TO")
	if to == "" {
		to = "/anything/public"
	}

	listener, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Fatalf("listen on :%s: %v", port, err)
	}

	grpcServer := grpc.NewServer()
	extprocv3.RegisterExternalProcessorServer(grpcServer, &server{from: from, to: to})

	errCh := make(chan error, 1)
	go func() {
		log.Printf("route-mutator-extproc listening on %s, rewriting %s -> %s", listener.Addr(), from, to)
		errCh <- grpcServer.Serve(listener)
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	select {
	case sig := <-sigCh:
		log.Printf("shutting down after %s", sig)
		grpcServer.GracefulStop()
	case err := <-errCh:
		if err != nil {
			log.Fatalf("serve: %v", err)
		}
	}
}
