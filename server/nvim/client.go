package nvim

import (
	"fmt"

	"gemini-cli/logger"
	"gemini-cli/types"

	"github.com/neovim/go-client/nvim"
)

// Client wraps the Neovim RPC client
type Client struct {
	nvim *nvim.Nvim
}

// NewClient creates a new Neovim RPC client
func NewClient(v *nvim.Nvim) *Client {
	return &Client{nvim: v}
}

// NotifyReady notifies Neovim that the server is ready
func (c *Client) NotifyReady(port int, authToken, workspace string) error {
	return c.nvim.ExecLua(`require('gemini-cli.server').on_ready(...)`, nil, port, authToken, workspace)
}

// OpenDiff opens a diff view for the given file
func (c *Client) OpenDiff(filePath, newContent string) error {
	logger.Debug("OpenDiff called for %s", filePath)

	var result interface{}
	err := c.nvim.ExecLua(`return require('gemini-cli.diff').open_diff(...)`, &result, filePath, newContent)

	if err != nil {
		logger.Error("OpenDiff failed: %v", err)
		return fmt.Errorf("failed to open diff: %w", err)
	}
	logger.Info("OpenDiff completed for %s", filePath)
	return nil
}

// CloseDiff closes the diff view for the given file and returns the final content
func (c *Client) CloseDiff(filePath string) (string, error) {
	logger.Debug("CloseDiff called for %s", filePath)

	var content string
	err := c.nvim.ExecLua(`return require('gemini-cli.diff').close_diff(...)`, &content, filePath)

	if err != nil {
		logger.Error("CloseDiff failed: %v", err)
		return "", fmt.Errorf("failed to close diff: %w", err)
	}
	logger.Debug("CloseDiff completed, content length=%d", len(content))
	return content, nil
}

// AcceptDiff accepts the diff changes and applies them to the original file
func (c *Client) AcceptDiff(filePath string) error {
	logger.Debug("AcceptDiff called for %s", filePath)

	var result interface{}
	err := c.nvim.ExecLua(`return require('gemini-cli.diff').accept_diff(...)`, &result, filePath)
	if err != nil {
		logger.Error("AcceptDiff failed: %v", err)
		return fmt.Errorf("failed to accept diff: %w", err)
	}
	logger.Info("AcceptDiff completed for %s", filePath)
	return nil
}

// RejectDiff rejects the diff changes and closes the diff view
func (c *Client) RejectDiff(filePath string) error {
	logger.Debug("RejectDiff called for %s", filePath)

	var result interface{}
	err := c.nvim.ExecLua(`return require('gemini-cli.diff').reject_diff(...)`, &result, filePath)
	if err != nil {
		logger.Error("RejectDiff failed: %v", err)
		return fmt.Errorf("failed to reject diff: %w", err)
	}
	logger.Info("RejectDiff completed for %s", filePath)
	return nil
}

// GetContext retrieves the current IDE context from Neovim
func (c *Client) GetContext() (*types.IdeContext, error) {
	var contextMap map[string]interface{}
	err := c.nvim.ExecLua(`return require('gemini-cli.context').get_context()`, &contextMap)
	if err != nil {
		logger.Error("GetContext failed: %v", err)
		return nil, fmt.Errorf("failed to get context: %w", err)
	}

	// Convert map to IdeContext struct
	// This is a simplified version; you may need more robust conversion
	context := &types.IdeContext{}
	// TODO: Implement proper map to struct conversion
	logger.Debug("Got context: %+v", contextMap)

	return context, nil
}

// RegisterCallbacks registers Lua callbacks for notifications
func (c *Client) RegisterCallbacks(
	onContextUpdate func(*types.IdeContext),
	onDiffAccepted func(string, string),
	onDiffRejected func(string),
) error {
	// Register Lua functions that will be called from Neovim
	// These will be exposed as global functions

	// Context update callback
	c.nvim.RegisterHandler("gemini_context_update", func(args ...interface{}) error {
		if len(args) > 0 {
			// Parse context from args
			// This is simplified; implement proper parsing
			logger.Debug("Context update received: %+v", args)
			// onContextUpdate(context)
		}
		return nil
	})

	// Diff accepted callback
	c.nvim.RegisterHandler("gemini_diff_accepted", func(args ...interface{}) error {
		if len(args) >= 2 {
			filePath, _ := args[0].(string)
			content, _ := args[1].(string)
			logger.Info("Diff accepted: %s", filePath)
			onDiffAccepted(filePath, content)
		}
		return nil
	})

	// Diff rejected callback
	c.nvim.RegisterHandler("gemini_diff_rejected", func(args ...interface{}) error {
		if len(args) >= 1 {
			filePath, _ := args[0].(string)
			logger.Info("Diff rejected: %s", filePath)
			onDiffRejected(filePath)
		}
		return nil
	})

	return nil
}
