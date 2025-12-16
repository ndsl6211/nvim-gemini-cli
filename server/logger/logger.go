package logger

import (
	"fmt"
	"log"
	"strings"
)

// LogLevel represents the logging level
type LogLevel int

const (
	// DEBUG level for detailed debugging information
	DEBUG LogLevel = iota
	// INFO level for general informational messages
	INFO
	// WARN level for warning messages
	WARN
	// ERROR level for error messages
	ERROR
)

var (
	currentLevel LogLevel = INFO
	levelNames            = map[LogLevel]string{
		DEBUG: "DEBUG",
		INFO:  "INFO",
		WARN:  "WARN",
		ERROR: "ERROR",
	}
)

// SetLevel sets the current logging level
func SetLevel(level LogLevel) {
	currentLevel = level
}

// SetLevelFromString sets the logging level from a string
func SetLevelFromString(levelStr string) error {
	switch strings.ToLower(levelStr) {
	case "debug":
		currentLevel = DEBUG
	case "info":
		currentLevel = INFO
	case "warn", "warning":
		currentLevel = WARN
	case "error":
		currentLevel = ERROR
	default:
		return fmt.Errorf("invalid log level: %s", levelStr)
	}
	return nil
}

// GetLevel returns the current logging level
func GetLevel() LogLevel {
	return currentLevel
}

// logf is the internal logging function
func logf(level LogLevel, format string, v ...interface{}) {
	if level >= currentLevel {
		prefix := levelNames[level]
		log.Printf("[%s] "+format, append([]interface{}{prefix}, v...)...)
	}
}

// Debug logs a debug message
func Debug(format string, v ...interface{}) {
	logf(DEBUG, format, v...)
}

// Info logs an info message
func Info(format string, v ...interface{}) {
	logf(INFO, format, v...)
}

// Warn logs a warning message
func Warn(format string, v ...interface{}) {
	logf(WARN, format, v...)
}

// Error logs an error message
func Error(format string, v ...interface{}) {
	logf(ERROR, format, v...)
}

// Fatal logs an error message and exits
func Fatal(format string, v ...interface{}) {
	logf(ERROR, format, v...)
	log.Fatalf(format, v...)
}
