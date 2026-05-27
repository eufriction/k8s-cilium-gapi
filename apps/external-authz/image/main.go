package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"

	corev3 "github.com/envoyproxy/go-control-plane/envoy/config/core/v3"
	authv3 "github.com/envoyproxy/go-control-plane/envoy/service/auth/v3"
	typev3 "github.com/envoyproxy/go-control-plane/envoy/type/v3"
	"golang.org/x/sync/errgroup"
	"google.golang.org/genproto/googleapis/rpc/status"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	grpc_health_v1 "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/protobuf/types/known/structpb"
)

const (
	defaultHTTPPort = 8080
	defaultGRPCPort = 9000
	shutdownTimeout = 5 * time.Second

	allowTokenHeader = "x-authz-token"
	allowTokenValue  = "allow"
	variantHeader    = "x-debug-token"
	variantValue     = "demo"
)

type authServer struct {
	authv3.UnimplementedAuthorizationServer
	logger *slog.Logger
}

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

	httpPort := getenvInt("HTTP_PORT", defaultHTTPPort)
	grpcPort := getenvInt("GRPC_PORT", defaultGRPCPort)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	httpSrv := &http.Server{
		Addr:              fmt.Sprintf(":%d", httpPort),
		Handler:           newHTTPMux(logger),
		ReadHeaderTimeout: 5 * time.Second,
	}

	grpcLis, err := net.Listen("tcp", fmt.Sprintf(":%d", grpcPort))
	if err != nil {
		logger.Error("failed to listen for gRPC", "error", err)
		os.Exit(1)
	}

	grpcSrv := grpc.NewServer()
	authv3.RegisterAuthorizationServer(grpcSrv, &authServer{logger: logger})
	grpc_health_v1.RegisterHealthServer(grpcSrv, healthServer{})

	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() error {
		logger.Info("starting HTTP ext_authz service", "port", httpPort)
		err := httpSrv.ListenAndServe()
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		return nil
	})
	g.Go(func() error {
		logger.Info("starting gRPC ext_authz service", "port", grpcPort)
		if err := grpcSrv.Serve(grpcLis); err != nil && gctx.Err() == nil {
			return err
		}
		return nil
	})

	<-ctx.Done()
	logger.Info("shutdown requested")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()

	grpcSrv.GracefulStop()
	if err := httpSrv.Shutdown(shutdownCtx); err != nil {
		logger.Error("HTTP shutdown failed", "error", err)
	}

	if err := g.Wait(); err != nil && !errors.Is(err, grpc.ErrServerStopped) {
		logger.Error("server exited with error", "error", err)
		os.Exit(1)
	}
}

func newHTTPMux(logger *slog.Logger) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok\n"))
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		decision := checkHTTP(r)
		logger.Info("HTTP ext_authz request",
			"method", r.Method,
			"path", r.URL.Path,
			"host", r.Host,
			"headers", flattenHTTPHeaders(r.Header),
			"allowed", decision.allowed,
			"reason", decision.reason,
		)
		if !decision.allowed {
			w.WriteHeader(http.StatusForbidden)
			_, _ = w.Write([]byte("denied by external-authz: " + decision.reason + "\n"))
			return
		}
		w.Header().Set("X-Ext-Authz-Result", "allowed-http")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("allowed\n"))
	})
	return mux
}

type decision struct {
	allowed bool
	reason  string
}

func checkHTTP(r *http.Request) decision {
	if strings.HasPrefix(r.URL.Path, "/variant-check") {
		if strings.EqualFold(r.Header.Get(variantHeader), variantValue) {
			return decision{allowed: true, reason: "variant token accepted"}
		}
		return decision{reason: "missing variant token"}
	}
	if strings.EqualFold(r.Header.Get(allowTokenHeader), allowTokenValue) {
		return decision{allowed: true, reason: "token accepted"}
	}
	return decision{reason: "missing auth token"}
}

func (s *authServer) Check(ctx context.Context, req *authv3.CheckRequest) (*authv3.CheckResponse, error) {
	httpAttrs := req.GetAttributes().GetRequest().GetHttp()
	headers := httpAttrs.GetHeaders()
	decision := checkGRPC(headers)

	s.logger.InfoContext(ctx, "gRPC ext_authz request",
		"method", httpAttrs.GetMethod(),
		"path", httpAttrs.GetPath(),
		"host", httpAttrs.GetHost(),
		"headers", flattenHeaderMap(headers),
		"allowed", decision.allowed,
		"reason", decision.reason,
	)

	if !decision.allowed {
		return &authv3.CheckResponse{
			Status: &status.Status{Code: int32(codes.PermissionDenied), Message: decision.reason},
			HttpResponse: &authv3.CheckResponse_DeniedResponse{
				DeniedResponse: &authv3.DeniedHttpResponse{
					Status: &typev3.HttpStatus{Code: typev3.StatusCode_Forbidden},
					Body:   "denied by external-authz: " + decision.reason + "\n",
				},
			},
		}, nil
	}

	return &authv3.CheckResponse{
		Status: &status.Status{Code: int32(codes.OK)},
		HttpResponse: &authv3.CheckResponse_OkResponse{
			OkResponse: &authv3.OkHttpResponse{
				Headers: []*corev3.HeaderValueOption{
					{Header: &corev3.HeaderValue{Key: "x-ext-authz-result", Value: "allowed-grpc"}},
				},
				DynamicMetadata: &structpb.Struct{Fields: map[string]*structpb.Value{
					"result": structpb.NewStringValue("allowed"),
				}},
			},
		},
	}, nil
}

func checkGRPC(headers map[string]string) decision {
	if strings.EqualFold(headers[allowTokenHeader], allowTokenValue) {
		return decision{allowed: true, reason: "token accepted"}
	}
	return decision{reason: "missing auth token"}
}

type healthServer struct {
	grpc_health_v1.UnimplementedHealthServer
}

func (healthServer) Check(context.Context, *grpc_health_v1.HealthCheckRequest) (*grpc_health_v1.HealthCheckResponse, error) {
	return &grpc_health_v1.HealthCheckResponse{Status: grpc_health_v1.HealthCheckResponse_SERVING}, nil
}

func (healthServer) Watch(_ *grpc_health_v1.HealthCheckRequest, srv grpc_health_v1.Health_WatchServer) error {
	return srv.Send(&grpc_health_v1.HealthCheckResponse{Status: grpc_health_v1.HealthCheckResponse_SERVING})
}

func getenvInt(key string, fallback int) int {
	raw := os.Getenv(key)
	if raw == "" {
		return fallback
	}
	v, err := strconv.Atoi(raw)
	if err != nil {
		return fallback
	}
	return v
}

func flattenHTTPHeaders(headers http.Header) string {
	keys := make([]string, 0, len(headers))
	for key := range headers {
		keys = append(keys, key)
	}
	slices.Sort(keys)

	parts := make([]string, 0, len(headers))
	for _, key := range keys {
		parts = append(parts, strings.ToLower(key)+"="+strings.Join(headers[key], ","))
	}
	return strings.Join(parts, " ")
}

func flattenHeaderMap(headers map[string]string) string {
	keys := make([]string, 0, len(headers))
	for key := range headers {
		keys = append(keys, key)
	}
	slices.Sort(keys)

	parts := make([]string, 0, len(headers))
	for _, key := range keys {
		parts = append(parts, key+"="+headers[key])
	}
	return strings.Join(parts, " ")
}
