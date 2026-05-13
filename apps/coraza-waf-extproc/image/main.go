package main

import (
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	coraza "github.com/corazawaf/coraza/v3"
	corev3 "github.com/envoyproxy/go-control-plane/envoy/config/core/v3"
	extprocv3 "github.com/envoyproxy/go-control-plane/envoy/service/ext_proc/v3"
	typev3 "github.com/envoyproxy/go-control-plane/envoy/type/v3"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type server struct {
	extprocv3.UnimplementedExternalProcessorServer
	waf coraza.WAF
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

		switch v := req.Request.(type) {
		case *extprocv3.ProcessingRequest_RequestHeaders:
			resp, err := s.handleRequestHeaders(v)
			if err != nil {
				return err
			}
			if err := stream.Send(resp); err != nil {
				return err
			}
			// If we sent an immediate response (blocked), end the stream
			if _, ok := resp.Response.(*extprocv3.ProcessingResponse_ImmediateResponse); ok {
				return nil
			}

		case *extprocv3.ProcessingRequest_ResponseHeaders:
			resp := &extprocv3.ProcessingResponse{
				Response: &extprocv3.ProcessingResponse_ResponseHeaders{
					ResponseHeaders: &extprocv3.HeadersResponse{
						Response: &extprocv3.CommonResponse{},
					},
				},
			}
			if err := stream.Send(resp); err != nil {
				return err
			}

		default:
			// For request body, response body, or trailers, acknowledge without changes
			resp := &extprocv3.ProcessingResponse{
				Response: &extprocv3.ProcessingResponse_RequestBody{
					RequestBody: &extprocv3.BodyResponse{
						Response: &extprocv3.CommonResponse{},
					},
				},
			}
			if err := stream.Send(resp); err != nil {
				return err
			}
		}
	}
}

func (s *server) handleRequestHeaders(v *extprocv3.ProcessingRequest_RequestHeaders) (*extprocv3.ProcessingResponse, error) {
	tx := s.waf.NewTransaction()

	headers := v.RequestHeaders.GetHeaders().GetHeaders()
	var path, method, host string
	for _, h := range headers {
		key := h.GetKey()
		val := headerVal(h)
		switch key {
		case ":path":
			path = val
		case ":method":
			method = val
		case ":authority":
			host = val
		default:
			tx.AddRequestHeader(key, val)
		}
	}

	// Feed URI and pseudo-headers into the transaction
	tx.ProcessURI(path, method, "HTTP/1.1")
	if host != "" {
		tx.AddRequestHeader("Host", host)
	}

	// Evaluate phase 1 (request headers)
	it := tx.ProcessRequestHeaders()
	tx.Close()

	if it != nil {
		log.Printf("BLOCKED: %s %s (host=%s, rule interrupted)", method, path, host)
		return &extprocv3.ProcessingResponse{
			Response: &extprocv3.ProcessingResponse_ImmediateResponse{
				ImmediateResponse: &extprocv3.ImmediateResponse{
					Status: &typev3.HttpStatus{
						Code: typev3.StatusCode_Forbidden,
					},
					Body: []byte("Forbidden: request blocked by WAF\n"),
				},
			},
		}, nil
	}

	// Request passed WAF evaluation — add header and continue
	return &extprocv3.ProcessingResponse{
		Response: &extprocv3.ProcessingResponse_RequestHeaders{
			RequestHeaders: &extprocv3.HeadersResponse{
				Response: &extprocv3.CommonResponse{
					HeaderMutation: &extprocv3.HeaderMutation{
						SetHeaders: []*corev3.HeaderValueOption{
							{
								Header: &corev3.HeaderValue{
									Key:      "x-waf-result",
									RawValue: []byte("pass"),
								},
							},
						},
					},
				},
			},
		},
	}, nil
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

	rulesFile := os.Getenv("CORAZA_RULES_FILE")
	if rulesFile == "" {
		rulesFile = "/etc/coraza/rules.conf"
	}

	// Initialize Coraza WAF engine
	waf, err := coraza.NewWAF(
		coraza.NewWAFConfig().
			WithDirectivesFromFile(rulesFile),
	)
	if err != nil {
		log.Fatalf("init WAF: %v", err)
	}
	log.Printf("WAF rules loaded from %s", rulesFile)

	listener, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Fatalf("listen on :%s: %v", port, err)
	}

	grpcServer := grpc.NewServer()
	extprocv3.RegisterExternalProcessorServer(grpcServer, &server{waf: waf})

	errCh := make(chan error, 1)
	go func() {
		log.Printf("coraza-waf-extproc listening on %s", listener.Addr())
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
