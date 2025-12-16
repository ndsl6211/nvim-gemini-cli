package types

// IdeContext represents the current state of the IDE
type IdeContext struct {
	WorkspaceState *WorkspaceState `json:"workspaceState,omitempty"`
}

// WorkspaceState contains workspace-level information
type WorkspaceState struct {
	OpenFiles []File `json:"openFiles,omitempty"`
	IsTrusted *bool  `json:"isTrusted,omitempty"`
}

// File represents an open file in the IDE
type File struct {
	Path         string  `json:"path"`
	Timestamp    int64   `json:"timestamp"`
	IsActive     *bool   `json:"isActive,omitempty"`
	Cursor       *Cursor `json:"cursor,omitempty"`
	SelectedText *string `json:"selectedText,omitempty"`
}

// Cursor represents cursor position in a file
type Cursor struct {
	Line      int `json:"line"`      // 1-based
	Character int `json:"character"` // 1-based
}

// OpenDiffRequest is the request to open a diff view
type OpenDiffRequest struct {
	FilePath   string `json:"filePath"`
	NewContent string `json:"newContent"`
}

// CloseDiffRequest is the request to close a diff view
type CloseDiffRequest struct {
	FilePath string `json:"filePath"`
}

// DiffAcceptedNotification is sent when user accepts a diff
type DiffAcceptedNotification struct {
	FilePath string `json:"filePath"`
	Content  string `json:"content"`
}

// DiffRejectedNotification is sent when user rejects a diff
type DiffRejectedNotification struct {
	FilePath string `json:"filePath"`
}

// DiscoveryFile represents the discovery file format
type DiscoveryFile struct {
	Port          int     `json:"port"`
	WorkspacePath string  `json:"workspacePath"`
	AuthToken     string  `json:"authToken"`
	IdeInfo       IdeInfo `json:"ideInfo"`
}

// IdeInfo contains IDE identification information
type IdeInfo struct {
	Name        string `json:"name"`
	DisplayName string `json:"displayName"`
}

// MCPRequest represents a generic MCP request
type MCPRequest struct {
	JSONRPC string                 `json:"jsonrpc"`
	ID      interface{}            `json:"id,omitempty"`
	Method  string                 `json:"method"`
	Params  map[string]interface{} `json:"params,omitempty"`
}

// MCPResponse represents a generic MCP response
type MCPResponse struct {
	JSONRPC string      `json:"jsonrpc"`
	ID      interface{} `json:"id,omitempty"`
	Result  interface{} `json:"result,omitempty"`
	Error   *MCPError   `json:"error,omitempty"`
}

// MCPError represents an MCP error
type MCPError struct {
	Code    int         `json:"code"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

// MCPNotification represents an MCP notification
type MCPNotification struct {
	JSONRPC string                 `json:"jsonrpc"`
	Method  string                 `json:"method"`
	Params  map[string]interface{} `json:"params,omitempty"`
}

// ToolCallResult represents the result of a tool call
type ToolCallResult struct {
	Content []ContentBlock `json:"content"`
	IsError bool           `json:"isError,omitempty"`
}

// ContentBlock represents content in MCP responses
type ContentBlock struct {
	Type string `json:"type"` // "text"
	Text string `json:"text"`
}
