package mcp

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"sync"

	"gemini-cli/nvim"
	"gemini-cli/types"
)

// Server implements the MCP HTTP server
type Server struct {
	authToken   string
	nvimClient  *nvim.Client
	tools       map[string]Tool
	mu          sync.RWMutex
	subscribers []chan types.MCPNotification
}

// Tool represents an MCP tool
type Tool struct {
	Name        string
	Description string
	Handler     func(map[string]interface{}) (*types.ToolCallResult, error)
}

// NewServer creates a new MCP server
func NewServer(authToken string, nvimClient *nvim.Client) *Server {
	s := &Server{
		authToken:   authToken,
		nvimClient:  nvimClient,
		tools:       make(map[string]Tool),
		subscribers: make([]chan types.MCPNotification, 0),
	}
	s.registerTools()
	return s
}

// registerTools registers all MCP tools
func (s *Server) registerTools() {
	// Register openDiff tool
	s.tools["openDiff"] = Tool{
		Name:        "openDiff",
		Description: "Open a diff view for a file",
		Handler:     s.handleOpenDiff,
	}

	// Register closeDiff tool
	s.tools["closeDiff"] = Tool{
		Name:        "closeDiff",
		Description: "Close a diff view for a file",
		Handler:     s.handleCloseDiff,
	}

	// Register acceptDiff tool
	s.tools["acceptDiff"] = Tool{
		Name:        "acceptDiff",
		Description: "Accept diff changes and apply them to the original file",
		Handler:     s.handleAcceptDiff,
	}

	// Register rejectDiff tool
	s.tools["rejectDiff"] = Tool{
		Name:        "rejectDiff",
		Description: "Reject diff changes and close the diff view",
		Handler:     s.handleRejectDiff,
	}
}

// handleOpenDiff handles the openDiff tool call
func (s *Server) handleOpenDiff(args map[string]interface{}) (*types.ToolCallResult, error) {
	var req types.OpenDiffRequest

	// Extract arguments
	filePath, ok := args["filePath"].(string)
	if !ok {
		return &types.ToolCallResult{
			Content: []types.ContentBlock{{Type: "text", Text: "Invalid filePath"}},
			IsError: true,
		}, nil
	}

	newContent, ok := args["newContent"].(string)
	if !ok {
		return &types.ToolCallResult{
			Content: []types.ContentBlock{{Type: "text", Text: "Invalid newContent"}},
			IsError: true,
		}, nil
	}

	req.FilePath = filePath
	req.NewContent = newContent

	// Call Neovim to open the diff
	err := s.nvimClient.OpenDiff(req.FilePath, req.NewContent)
	if err != nil {
		return &types.ToolCallResult{
			Content: []types.ContentBlock{{Type: "text", Text: fmt.Sprintf("Failed to open diff: %v", err)}},
			IsError: true,
		}, nil
	}

	// Return empty content on success
	return &types.ToolCallResult{
		Content: []types.ContentBlock{},
		IsError: false,
	}, nil
}

// handleCloseDiff handles the closeDiff tool call
func (s *Server) handleCloseDiff(args map[string]interface{}) (*types.ToolCallResult, error) {
	filePath, ok := args["filePath"].(string)
	if !ok {
		return &types.ToolCallResult{
			Content: []types.ContentBlock{{Type: "text", Text: "Invalid filePath"}},
			IsError: true,
		}, nil
	}

	// Call Neovim to close the diff and get final content
	content, err := s.nvimClient.CloseDiff(filePath)
	if err != nil {
		return &types.ToolCallResult{
			Content: []types.ContentBlock{{Type: "text", Text: fmt.Sprintf("Failed to close diff: %v", err)}},
			IsError: true,
		}, nil
	}

	// Return the final content
	return &types.ToolCallResult{
		Content: []types.ContentBlock{{Type: "text", Text: content}},
		IsError: false,
	}, nil
}

// handleAcceptDiff handles the acceptDiff tool call
func (s *Server) handleAcceptDiff(args map[string]interface{}) (*types.ToolCallResult, error) {
	filePath, ok := args["filePath"].(string)
	if !ok {
		return &types.ToolCallResult{
			Content: []types.ContentBlock{{Type: "text", Text: "Invalid filePath"}},
			IsError: true,
		}, nil
	}

	// Call Neovim to accept the diff
	err := s.nvimClient.AcceptDiff(filePath)
	if err != nil {
		return &types.ToolCallResult{
			Content: []types.ContentBlock{{Type: "text", Text: fmt.Sprintf("Failed to accept diff: %v", err)}},
			IsError: true,
		}, nil
	}

	// Return empty content on success
	return &types.ToolCallResult{
		Content: []types.ContentBlock{},
		IsError: false,
	}, nil
}

// handleRejectDiff handles the rejectDiff tool call
func (s *Server) handleRejectDiff(args map[string]interface{}) (*types.ToolCallResult, error) {
	filePath, ok := args["filePath"].(string)
	if !ok {
		return &types.ToolCallResult{
			Content: []types.ContentBlock{{Type: "text", Text: "Invalid filePath"}},
			IsError: true,
		}, nil
	}

	// Call Neovim to reject the diff
	err := s.nvimClient.RejectDiff(filePath)
	if err != nil {
		return &types.ToolCallResult{
			Content: []types.ContentBlock{{Type: "text", Text: fmt.Sprintf("Failed to reject diff: %v", err)}},
			IsError: true,
		}, nil
	}

	// Return empty content on success
	return &types.ToolCallResult{
		Content: []types.ContentBlock{},
		IsError: false,
	}, nil
}

// AuthMiddleware validates the Bearer token and handles CORS
func (s *Server) AuthMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Set CORS headers for all responses
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, Accept, X-Requested-With, Cache-Control")

		// Handle preflight OPTIONS request
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		authHeader := r.Header.Get("Authorization")
		expectedAuth := "Bearer " + s.authToken

		if authHeader != expectedAuth {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		next(w, r)
	}
}

// HandleMCP handles MCP requests
func (s *Server) HandleMCP(w http.ResponseWriter, r *http.Request) {
	// Check if this is an SSE connection request
	// Gemini CLI sends "application/json, text/event-stream" in Accept header
	// The client uses GET for SSE connections after receiving 202 Accepted from initialization
	if r.Method == http.MethodGet && strings.Contains(r.Header.Get("Accept"), "text/event-stream") {
		s.HandleSSE(w, r)
		return
	}

	// Set Content-Type for JSON-RPC responses
	w.Header().Set("Content-Type", "application/json")

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req types.MCPRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}

	log.Printf("Received MCP request: %s (ID: %v)", req.Method, req.ID)

	// Handle different MCP methods
	switch req.Method {
	case "initialize":
		s.handleInitialize(w, &req)
	case "tools/list":
		s.handleToolsList(w, &req)
	case "tools/call":
		s.handleToolsCall(w, &req)
	case "notifications/initialized":
		// Vital for StreamableHTTPClientTransport: This signals the client to establish the SSE connection
		w.WriteHeader(http.StatusAccepted)
	default:
		s.sendError(w, req.ID, -32601, "Method not found")
	}
}

// handleInitialize handles MCP initialize request
func (s *Server) handleInitialize(w http.ResponseWriter, req *types.MCPRequest) {
	response := types.MCPResponse{
		JSONRPC: "2.0",
		ID:      req.ID,
		Result: map[string]interface{}{
			"protocolVersion": "2025-06-18",
			"serverInfo": map[string]string{
				"name":    "nvim-gemini-cli",
				"version": "0.1.0",
			},
			"capabilities": map[string]interface{}{
				"tools": map[string]bool{
					"listChanged": false,
				},
			},
		},
	}

	json.NewEncoder(w).Encode(response)
}

// handleToolsList handles MCP tools/list request
func (s *Server) handleToolsList(w http.ResponseWriter, req *types.MCPRequest) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	tools := make([]map[string]interface{}, 0, len(s.tools))
	for _, tool := range s.tools {
		tools = append(tools, map[string]interface{}{
			"name":        tool.Name,
			"description": tool.Description,
			"inputSchema": map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"filePath": map[string]string{
						"type":        "string",
						"description": "Absolute path to the file",
					},
					"newContent": map[string]string{
						"type":        "string",
						"description": "New content for the file (for openDiff)",
					},
				},
				"required": []string{"filePath"},
			},
		})
	}

	response := types.MCPResponse{
		JSONRPC: "2.0",
		ID:      req.ID,
		Result: map[string]interface{}{
			"tools": tools,
		},
	}

	json.NewEncoder(w).Encode(response)
}

// handleToolsCall handles MCP tools/call request
func (s *Server) handleToolsCall(w http.ResponseWriter, req *types.MCPRequest) {
	toolName, ok := req.Params["name"].(string)
	if !ok {
		log.Printf("ERROR: Missing tool name in request")
		s.sendError(w, req.ID, -32602, "Missing tool name")
		return
	}

	s.mu.RLock()
	tool, exists := s.tools[toolName]
	s.mu.RUnlock()

	if !exists {
		log.Printf("ERROR: Tool not found: %s", toolName)
		s.sendError(w, req.ID, -32602, "Tool not found")
		return
	}

	args, ok := req.Params["arguments"].(map[string]interface{})
	if !ok {
		args = make(map[string]interface{})
	}

	// Call the tool handler
	result, err := tool.Handler(args)
	if err != nil {
		log.Printf("ERROR: Tool handler failed for %s: %v", toolName, err)
		s.sendError(w, req.ID, -32603, err.Error())
		return
	}

	response := types.MCPResponse{
		JSONRPC: "2.0",
		ID:      req.ID,
		Result:  result,
	}

	json.NewEncoder(w).Encode(response)
}

// SendNotification sends an MCP notification
func (s *Server) SendNotification(method string, params map[string]interface{}) {
	notification := types.MCPNotification{
		JSONRPC: "2.0",
		Method:  method,
		Params:  params,
	}

	s.mu.RLock()
	defer s.mu.RUnlock()

	for i, sub := range s.subscribers {
		select {
		case sub <- notification:
			// Notification sent
		default:
			log.Printf("Warning: notification channel full for subscriber %d, dropping notification", i)
		}
	}
}

// SendContextUpdate sends an ide/contextUpdate notification
func (s *Server) SendContextUpdate(context *types.IdeContext) {
	params := map[string]interface{}{
		"workspaceState": context.WorkspaceState,
	}
	s.SendNotification("ide/contextUpdate", params)
}

// SendDiffAccepted sends an ide/diffAccepted notification
func (s *Server) SendDiffAccepted(filePath, content string) {
	params := map[string]interface{}{
		"filePath": filePath,
		"content":  content,
	}
	s.SendNotification("ide/diffAccepted", params)
}

// SendDiffRejected sends an ide/diffRejected notification
func (s *Server) SendDiffRejected(filePath string) {
	params := map[string]interface{}{
		"filePath": filePath,
	}
	s.SendNotification("ide/diffRejected", params)
}

// sendError sends an MCP error response
func (s *Server) sendError(w http.ResponseWriter, id interface{}, code int, message string) {
	response := types.MCPResponse{
		JSONRPC: "2.0",
		ID:      id,
		Error: &types.MCPError{
			Code:    code,
			Message: message,
		},
	}
	json.NewEncoder(w).Encode(response)
}
