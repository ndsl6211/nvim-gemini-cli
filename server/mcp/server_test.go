package mcp

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestAuthMiddleware(t *testing.T) {
	authToken := "test-token"
	s := &Server{
		authToken: authToken,
	}

	handler := s.AuthMiddleware(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	tests := []struct {
		name       string
		authHeader string
		wantCode   int
	}{
		{
			name:       "valid token",
			authHeader: "Bearer test-token",
			wantCode:   http.StatusOK,
		},
		{
			name:       "invalid token",
			authHeader: "Bearer wrong-token",
			wantCode:   http.StatusUnauthorized,
		},
		{
			name:       "missing bearer prefix",
			authHeader: "test-token",
			wantCode:   http.StatusUnauthorized,
		},
		{
			name:       "missing header",
			authHeader: "",
			wantCode:   http.StatusUnauthorized,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req, _ := http.NewRequest("POST", "/mcp", nil)
			if tt.authHeader != "" {
				req.Header.Set("Authorization", tt.authHeader)
			}
			rr := httptest.NewRecorder()

			handler.ServeHTTP(rr, req)

			if rr.Code != tt.wantCode {
				t.Errorf("AuthMiddleware() %s status code = %v, want %v", tt.name, rr.Code, tt.wantCode)
			}
		})
	}
}

func TestHandleInitialize(t *testing.T) {
	s := &Server{}
	rr := httptest.NewRecorder()

	// Create mock initialization request
	// Using anonymous struct to match the expected JSON structure
	reqBody := `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-client","version":"1.0.0"}}}`
	req, _ := http.NewRequest("POST", "/mcp", strings.NewReader(reqBody))

	s.HandleMCP(rr, req)

	if rr.Code != http.StatusOK {
		t.Errorf("HandleMCP(initialize) status code = %v, want %v", rr.Code, http.StatusOK)
	}

	var resp map[string]interface{}
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}

	// Basic check of response structure
	if resp["id"].(float64) != 1 {
		t.Errorf("HandleMCP(initialize) response id = %v, want 1", resp["id"])
	}
}
