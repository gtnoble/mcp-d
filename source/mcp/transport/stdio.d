module mcp.transport.stdio;

import std.stdio;
import std.json;
import std.string : strip;

import mcp.protocol;

/// Transport base interface
interface Transport {
    void handleMessage(JSONValue message);
    void sendMessage(JSONValue message);
    void run();
    void close();
}

/// Stdio transport implementation
class StdioTransport : Transport {
    private {
        void delegate(JSONValue) messageHandler;
        File input;
        File output;
        bool closed;
    }
    
    this(void delegate(JSONValue) handler, 
         File input = std.stdio.stdin,
         File output = std.stdio.stdout) {
        this.messageHandler = handler;
        this.input = input;
        this.output = output;
    }
    
    /// Handle incoming message
    void handleMessage(JSONValue message) {
        messageHandler(message);
    }
    
    /// Send message to output
    void sendMessage(JSONValue message) {
        synchronized(this) {
            if (!closed) {
                output.writeln(message.toString());
                output.flush();
            }
        }
    }
    
    /// Main message loop
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
    
    /// Close transport
    void close() {
        synchronized(this) {
            closed = true;
            input.close();
            output.close();
        }
    }
}

/// Create stdio transport with line buffering
StdioTransport createStdioTransport(void delegate(JSONValue) handler) {
    // Set up line buffering
    stdin.setvbuf(1024, _IOLBF);
    stdout.setvbuf(1024, _IOLBF);
    
    return new StdioTransport(handler);
}
