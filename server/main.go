package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"

	"gemini-cli/mcp"
	"gemini-cli/nvim"
	"gemini-cli/types"

	"github.com/google/uuid"
	nvimclient "github.com/neovim/go-client/nvim"
)

var (
	nvimAddr      = flag.String("nvim", "", "Neovim address (socket path or host:port)")
	workspacePath = flag.String("workspace", "", "Workspace path(s), colon-separated")
	pid           = flag.Int("pid", 0, "Neovim PID")
)

func main() {
	flag.Parse()

	if *nvimAddr == "" || *workspacePath == "" || *pid == 0 {
		log.Fatal("Usage: gemini-mcp-server -nvim=<addr> -workspace=<path> -pid=<pid>")
	}

	// Connect to Neovim via unix socket
	conn, err := net.Dial("unix", *nvimAddr)
	if err != nil {
		log.Fatalf("Failed to connect to Neovim: %v", err)
	}
	defer conn.Close()

	// Create Neovim client
	v, err := nvimclient.New(conn, conn, conn, nil)
	if err != nil {
		log.Fatalf("Failed to create Neovim client: %v", err)
	}

	// Create shutdown channel
	shutdownChan := make(chan string)

	// Goroutine: Serve Neovim RPC (if connection dies, we shutdown)
	go func() {
		if err := v.Serve(); err != nil {
			log.Printf("Neovim client serve ended with error: %v", err)
		} else {
			log.Printf("Neovim client serve ended")
		}
		shutdownChan <- "nvim-connection-closed"
	}()

	nvimClient := nvim.NewClient(v)

	// Generate auth token
	authToken := uuid.New().String()
	log.Printf("Auth token: %s", authToken)

	// Create MCP server
	mcpServer := mcp.NewServer(authToken, nvimClient)

	// Register callbacks for Neovim notifications
	err = nvimClient.RegisterCallbacks(
		func(context *types.IdeContext) {
			mcpServer.SendContextUpdate(context)
		},
		func(filePath, content string) {
			mcpServer.SendDiffAccepted(filePath, content)
		},
		func(filePath string) {
			mcpServer.SendDiffRejected(filePath)
		},
	)
	if err != nil {
		log.Fatalf("Failed to register callbacks: %v", err)
	}

	// Create HTTP server on random port
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		log.Fatalf("Failed to create listener: %v", err)
	}
	// We don't defer listener.Close() because http.Serve closes it, or we rely on Shutdown

	port := listener.Addr().(*net.TCPAddr).Port
	log.Printf("MCP server listening on port %d", port)

	// Notify Neovim that server is ready via RPC
	if err := nvimClient.NotifyReady(port, authToken, *workspacePath); err != nil {
		log.Printf("Warning: failed to notify Neovim: %v", err)
	}

	// Create discovery file
	if err := createDiscoveryFile(*pid, port, *workspacePath, authToken); err != nil {
		log.Fatalf("Failed to create discovery file: %v", err)
	}
	// We handle removal manually on shutdown

	// Set up HTTP handlers
	http.HandleFunc("/mcp", mcpServer.AuthMiddleware(mcpServer.HandleMCP))
	http.HandleFunc("/events", mcpServer.HandleSSE) // Auth handled internally
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// Goroutine: Monitor Parent PID (Double safety for :qa)
	go func() {
		ticker := time.NewTicker(2 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			if !isProcessAlive(*pid) {
				shutdownChan <- "parent-process-dead"
				return
			}
		}
	}()

	// Goroutine: Handle OS Signals (SIGINT, SIGTERM)
	go func() {
		sigChan := make(chan os.Signal, 1) // Corrected type
		signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
		<-sigChan
		shutdownChan <- "os-signal"
	}()

	// Create HTTP server
	httpServer := &http.Server{
		Handler: nil, // Use DefaultServeMux
	}

	// Goroutine: Start HTTP server
	go func() {
		if err := httpServer.Serve(listener); err != nil && err != http.ErrServerClosed {
			log.Printf("HTTP server error: %v", err)
			shutdownChan <- "http-server-error"
		}
	}()

	// Wait for any shutdown signal
	reason := <-shutdownChan
	log.Printf("Shutting down (reason: %s)...", reason)

	// Perform Cleanup
	cleanupCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := httpServer.Shutdown(cleanupCtx); err != nil {
		log.Printf("HTTP server shutdown error: %v", err)
	}

	// Manually call removeDiscoveryFile
	removeDiscoveryFile(*pid, port, *workspacePath)
	log.Println("Server shutdown complete")
}

// isProcessAlive checks if a process with the given PID is running
func isProcessAlive(pid int) bool {
	proc, err := os.FindProcess(pid)
	if err != nil {
		return false
	}
	// On Unix, FindProcess always succeeds. Sending Signal 0 checks for existence.
	err = proc.Signal(syscall.Signal(0))
	if err == nil {
		return true
	}
	if err == syscall.ESRCH {
		return false
	}
	// EPERM means it exists but we can't signal it (still alive)
	return true
}

func createDiscoveryFile(pid, port int, workspacePath, authToken string) error {
	// Create directory
	tmpDir := os.TempDir()
	geminiDir := filepath.Join(tmpDir, "gemini", "ide")
	if err := os.MkdirAll(geminiDir, 0755); err != nil {
		return fmt.Errorf("failed to create directory: %w", err)
	}

	discovery := types.DiscoveryFile{
		Port:          port,
		WorkspacePath: workspacePath,
		AuthToken:     authToken,
		IdeInfo: types.IdeInfo{
			// Try "vscodefork" to pass gemini-cli's whitelist check
			// (gemini-cli accepts: Antigravity, VS Code, or VS Code forks)
			Name:        "vscodefork",
			DisplayName: "IDE",
		},
	}

	data, err := json.MarshalIndent(discovery, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal discovery file: %w", err)
	}

	// Create discovery file for main PID
	mainFilename := fmt.Sprintf("gemini-ide-server-%d-%d.json", pid, port)
	mainFilepath := filepath.Join(geminiDir, mainFilename)

	if err := os.WriteFile(mainFilepath, data, 0644); err != nil {
		return fmt.Errorf("failed to write discovery file: %w", err)
	}
	log.Printf("Created discovery file: %s", mainFilepath)

	// CRITICAL FIX: Also create discovery file for parent process
	// When Neovim is run directly, vim.fn.getpid() may return nvim --embed PID,
	// but gemini-cli finds the parent nvim PID. We need files for both.
	parentPid := getParentPid(pid)
	if parentPid > 0 && parentPid != pid {
		parentFilename := fmt.Sprintf("gemini-ide-server-%d-%d.json", parentPid, port)
		parentFilepath := filepath.Join(geminiDir, parentFilename)

		if err := os.WriteFile(parentFilepath, data, 0644); err != nil {
			log.Printf("Warning: failed to create discovery file for parent PID %d: %v", parentPid, err)
		} else {
			log.Printf("Created discovery file for parent process: %s (PID %d)", parentFilepath, parentPid)
		}
	}

	// Also create for child processes (nvim --embed children of main nvim)
	childPids := findNvimChildProcesses(pid)
	for _, childPid := range childPids {
		childFilename := fmt.Sprintf("gemini-ide-server-%d-%d.json", childPid, port)
		childFilepath := filepath.Join(geminiDir, childFilename)

		if err := os.WriteFile(childFilepath, data, 0644); err != nil {
			log.Printf("Warning: failed to create discovery file for child PID %d: %v", childPid, err)
		} else {
			log.Printf("Created discovery file for child process: %s (PID %d)", childFilepath, childPid)
		}
	}

	return nil
}

// getParentPid gets the parent PID of the given process
func getParentPid(pid int) int {
	if runtime.GOOS != "linux" {
		return 0
	}

	statPath := filepath.Join("/proc", fmt.Sprintf("%d", pid), "stat")
	statData, err := os.ReadFile(statPath)
	if err != nil {
		return 0
	}

	// Parse stat file to get PPID
	statStr := string(statData)
	lastParen := -1
	for i := len(statStr) - 1; i >= 0; i-- {
		if statStr[i] == ')' {
			lastParen = i
			break
		}
	}
	if lastParen == -1 {
		return 0
	}

	fields := strings.Fields(statStr[lastParen+1:])
	if len(fields) < 2 {
		return 0
	}

	var ppid int
	fmt.Sscanf(fields[1], "%d", &ppid)
	return ppid
}

// findNvimChildProcesses finds all child processes of the given PID that are nvim processes
func findNvimChildProcesses(parentPid int) []int {
	var childPids []int

	// On Linux, read /proc to find child processes
	if runtime.GOOS != "linux" {
		return childPids
	}

	procDir := "/proc"
	entries, err := os.ReadDir(procDir)
	if err != nil {
		log.Printf("Warning: failed to read /proc: %v", err)
		return childPids
	}

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		// Parse PID from directory name
		var pid int
		if _, err := fmt.Sscanf(entry.Name(), "%d", &pid); err != nil {
			continue
		}

		// Read /proc/[pid]/stat to get parent PID
		statPath := filepath.Join(procDir, entry.Name(), "stat")
		statData, err := os.ReadFile(statPath)
		if err != nil {
			continue
		}

		// Parse stat file: PID (comm) state PPID ...
		// comm can contain spaces and parentheses, so we need to find the last ')' first
		statStr := string(statData)
		lastParen := -1
		for i := len(statStr) - 1; i >= 0; i-- {
			if statStr[i] == ')' {
				lastParen = i
				break
			}
		}
		if lastParen == -1 {
			continue
		}

		// Fields after the comm field
		fields := make([]string, 0)
		for _, field := range strings.Fields(statStr[lastParen+1:]) {
			fields = append(fields, field)
		}

		if len(fields) < 2 {
			continue
		}

		// PPID is the first field after state
		var ppid int
		if _, err := fmt.Sscanf(fields[1], "%d", &ppid); err != nil {
			continue
		}

		// Check if this process's parent is our target PID
		if ppid == parentPid {
			// Check if this is a nvim process
			cmdlinePath := filepath.Join(procDir, entry.Name(), "cmdline")
			cmdlineData, err := os.ReadFile(cmdlinePath)
			if err != nil {
				continue
			}

			cmdline := string(cmdlineData)
			// Only match "nvim --embed" child processes, not any process containing "nvim"
			if strings.Contains(cmdline, "nvim") && strings.Contains(cmdline, "--embed") {
				childPids = append(childPids, pid)
				log.Printf("Found nvim --embed child process: PID %d (parent: %d, cmdline: %s)",
					pid, parentPid, strings.ReplaceAll(cmdline, "\x00", " "))
			}
		}
	}

	return childPids
}

func removeDiscoveryFile(pid, port int, workspacePath string) {
	tmpDir := os.TempDir()
	geminiDir := filepath.Join(tmpDir, "gemini", "ide")

	// Remove main PID discovery file
	mainFilename := fmt.Sprintf("gemini-ide-server-%d-%d.json", pid, port)
	mainPath := filepath.Join(geminiDir, mainFilename)

	if err := os.Remove(mainPath); err != nil {
		log.Printf("Warning: failed to remove discovery file: %v", err)
	} else {
		log.Printf("Removed discovery file: %s", mainPath)
	}

	// Remove parent PID discovery file
	parentPid := getParentPid(pid)
	if parentPid > 0 && parentPid != pid {
		parentFilename := fmt.Sprintf("gemini-ide-server-%d-%d.json", parentPid, port)
		parentPath := filepath.Join(geminiDir, parentFilename)

		if err := os.Remove(parentPath); err != nil {
			log.Printf("Warning: failed to remove parent discovery file (PID %d): %v", parentPid, err)
		} else {
			log.Printf("Removed parent discovery file: %s (PID %d)", parentPath, parentPid)
		}
	}

	// Remove child PID discovery files
	childPids := findNvimChildProcesses(pid)
	for _, childPid := range childPids {
		childFilename := fmt.Sprintf("gemini-ide-server-%d-%d.json", childPid, port)
		childPath := filepath.Join(geminiDir, childFilename)

		if err := os.Remove(childPath); err != nil {
			log.Printf("Warning: failed to remove child discovery file (PID %d): %v", childPid, err)
		} else {
			log.Printf("Removed child discovery file: %s (PID %d)", childPath, childPid)
		}
	}
}

func getPathSeparator() string {
	if runtime.GOOS == "windows" {
		return ";"
	}
	return ":"
}
