/**
 * Standard I/O transport for MCP.
 *
 * This module provides a transport implementation that uses standard input
 * and output for communication. It handles message framing, parsing, and
 * error handling according to the MCP protocol.
 *
 * The module includes:
 * - Transport interface definition
 * - StdioTransport implementation
 * - Helper function for creating properly configured transports
 *
 * Example:
 * ```d
 * // Create a transport with default stdin/stdout
 * auto transport = createStdioTransport();
 *
 * // Set message handler
 * transport.setMessageHandler((JSONValue message) {
 *     writeln("Received: ", message);
 *     transport.sendMessage(JSONValue(["response": "Hello"]));
 * });
 *
 * // Start processing messages
 * transport.run();
 * ```
 */
module mcp.transport.stdio;

import std.stdio;
import std.json;
import std.string : strip;

import mcp.protocol;
import mcp.transport.base : Transport;

/**
 * Standard I/O transport implementation.
 *
 * This class implements the Transport interface using standard input
 * and output streams. It handles message framing, parsing, and error
 * handling according to the MCP protocol.
 */
class StdioTransport : Transport {
    private {
        void delegate(JSONValue) messageHandler;
        File input;
        File output;
        bool closed;
    }
    
    this(File input = std.stdio.stdin, File output = std.stdio.stdout) {
        this.input = input;
        this.output = output;
    }

    /**
     * Sets the message handler function.
     *
     * The message handler is called for each valid JSON message
     * received from the input stream.
     *
     * Params:
     *   handler = The function to call for each message
     */
    void setMessageHandler(void delegate(JSONValue) handler) {
        this.messageHandler = handler;
    }
    
    /**
     * Handles an incoming message.
     *
     * This method passes the message to the registered handler.
     *
     * Params:
     *   message = The JSON message to handle
     */
    void handleMessage(JSONValue message) {
        messageHandler(message);
    }
    
    /**
     * Sends a message to the output stream.
     *
     * This method serializes the JSON message and writes it
     * to the output stream with proper framing.
     *
     * Params:
     *   message = The JSON message to send
     */
    void sendMessage(JSONValue message) {
        synchronized(this) {
            if (!closed) {
                output.writeln(message.toString());
                output.flush();
            }
        }
    }
    
    /**
     * Starts the main message processing loop.
     *
     * This method reads messages from the input stream, parses them,
     * and passes them to the message handler. It continues until
     * the input stream is closed or an error occurs.
     */
    void run() {
        while (!input.eof && !closed) {
            try {
                // Read line
                auto line = input.readln().strip();
                if (line.length == 0) continue;
                
                // Parse JSON
                JSONValue message;
                try {
                    message = parseJSON(line);
                }
                catch (JSONException e) {
                    // Send parse error
                    auto response = Response.makeError(
                        JSONValue(null),
                        ErrorCode.parseError,
                        "Invalid JSON: " ~ e.msg
                    );
                    sendMessage(response.toJSON());
                    continue;
                }
                
                // Handle message
                handleMessage(message);
            }
            catch (Exception e) {
                // Send internal error
                auto response = Response.makeError(
                    JSONValue(null),
                    ErrorCode.internalError,
                    "Internal error: " ~ e.msg
                );
                sendMessage(response.toJSON());
            }
        }
    }
    
    /**
     * Closes the transport.
     *
     * This method closes the input and output streams and
     * prevents further message processing.
     */
    void close() {
        synchronized(this) {
            closed = true;
            input.close();
            output.close();
        }
    }
}

/**
 * Creates a properly configured stdio transport.
 *
 * This function creates a StdioTransport with line buffering
 * configured for optimal performance.
 *
 * Returns:
 *   A new StdioTransport instance
 */
StdioTransport createStdioTransport() {
    // Set up line buffering
    stdin.setvbuf(1024, _IOLBF);
    stdout.setvbuf(1024, _IOLBF);
    
    return new StdioTransport();
}
