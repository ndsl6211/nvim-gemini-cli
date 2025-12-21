// Package mcp implements the Model Context Protocol server for Gemini CLI.
package mcp

import (
	"encoding/json"
	"fmt"
	"gemini-cli/types"
	"log"
	"net/http"
)

// HandleSSE handles Server-Sent Events connections
func (s *Server) HandleSSE(w http.ResponseWriter, r *http.Request) {
	// CRITICAL: Set headers FIRST, before any error checks
	// This ensures clients get the correct content-type even if auth fails
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	// Check authentication AFTER setting headers
	authHeader := r.Header.Get("Authorization")
	expectedAuth := "Bearer " + s.authToken

	if authHeader != expectedAuth {
		// For SSE, we need to send an error event, not use http.Error
		_, _ = fmt.Fprintf(w, "event: error\ndata: {\"error\":\"Unauthorized\"}\n\n")
		if f, ok := w.(http.Flusher); ok {
			f.Flush()
		}
		return
	}

	// Create notification channel for this connection
	notifChan := make(chan types.MCPNotification, 10)

	s.mu.Lock()
	s.subscribers = append(s.subscribers, notifChan)
	s.mu.Unlock()

	// Remove subscriber when connection closes
	defer func() {
		s.mu.Lock()
		for i, sub := range s.subscribers {
			if sub == notifChan {
				s.subscribers = append(s.subscribers[:i], s.subscribers[i+1:]...)
				break
			}
		}
		s.mu.Unlock()
		close(notifChan)
	}()

	// Get Flusher for SSE
	flusher, ok := w.(http.Flusher)
	if !ok {
		_, _ = fmt.Fprintf(w, "event: error\ndata: {\"error\":\"Streaming unsupported\"}\n\n")
		return
	}

	log.Printf("SSE client connected")

	// Send an initial comment to keep connection alive
	_, _ = fmt.Fprintf(w, ": connected\n\n")
	flusher.Flush()

	// Send notifications to client
	for {
		select {
		case <-r.Context().Done():
			log.Printf("SSE client disconnected")
			return
		case notif := <-notifChan:
			data, err := json.Marshal(notif)
			if err != nil {
				log.Printf("Failed to marshal notification: %v", err)
				continue
			}
			_, _ = fmt.Fprintf(w, "data: %s\n\n", data)
			flusher.Flush()
		}
	}
}
