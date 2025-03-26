module mcp.protocol;

import std.json;

/// Protocol version supported by this implementation
const string PROTOCOL_VERSION = "2024-11-05";

/// JSON-RPC version used by MCP
const string JSONRPC_VERSION = "2.0";

/// Standard JSON-RPC error codes
enum ErrorCode {
    parseError = -32700,        // Invalid JSON
    invalidRequest = -32600,    // Not a valid request object
    methodNotFound = -32601,    // Method not found
    invalidParams = -32602,     // Invalid method parameters
    internalError = -32603      // Internal server error
}

/// Base MCP error exception
class MCPError : Exception {
    int code;
    string details;
    
    this(int code, string message, string details = null, 
         string file = __FILE__, size_t line = __LINE__) {
        this.code = code;
        this.details = details;
        super(message, file, line);
    }
    
    JSONValue toJSON() const {
        auto error = JSONValue([
            "code": JSONValue(code),
            "message": JSONValue(msg)
        ]);
        
        if (details !is null) {
            error["data"] = JSONValue(details);
        }
        
        return JSONValue([
            "jsonrpc": JSONValue(JSONRPC_VERSION),
            "error": error
        ]);
    }
}

/// JSON-RPC request
struct Request {
    string jsonrpc = JSONRPC_VERSION;  // Must be "2.0"
    string method;                      // Method to call
    JSONValue params;                   // Method parameters
    JSONValue id;                       // Request ID (null for notifications)
    
    this(string method, JSONValue params = JSONValue(null), 
         JSONValue id = JSONValue(null)) {
        this.method = method;
        this.params = params;
        this.id = id;
    }
    
    /// Create from JSON
    static Request fromJSON(JSONValue json) {
        Request req;
        
        // Validate JSON-RPC version
        if ("jsonrpc" !in json || json["jsonrpc"].str != JSONRPC_VERSION) {
            throw new MCPError(ErrorCode.invalidRequest,
                "Invalid JSON-RPC version");
        }
        
        // Validate method
        if ("method" !in json || json["method"].type != JSONType.string) {
            throw new MCPError(ErrorCode.invalidRequest,
                "Missing or invalid method");
        }
        req.method = json["method"].str;
        
        // Get parameters if present
        if ("params" in json) {
            if (json["params"].type != JSONType.object &&
                json["params"].type != JSONType.array) {
                throw new MCPError(ErrorCode.invalidRequest,
                    "Parameters must be object or array");
            }
            req.params = json["params"];
        }
        
        // Get ID if present (null for notifications)
        if ("id" in json) {
            if (json["id"].type != JSONType.string &&
                json["id"].type != JSONType.integer &&
                json["id"].type != JSONType.null_) {
                throw new MCPError(ErrorCode.invalidRequest,
                    "Invalid request ID type");
            }
            req.id = json["id"];
        }
        
        return req;
    }
    
    /// Convert to JSON
    JSONValue toJSON() const {
        auto json = JSONValue([
            "jsonrpc": JSONValue(JSONRPC_VERSION),
            "method": JSONValue(method)
        ]);
        
        if (params.type != JSONType.null_) {
            json["params"] = params;
        }
        
        if (id.type != JSONType.null_) {
            json["id"] = id;
        }
        
        return json;
    }
    
    /// Returns true if this is a notification (no ID)
    bool isNotification() const {
        return id.type == JSONType.null_;
    }
}

/// JSON-RPC response
struct Response {
    string jsonrpc = JSONRPC_VERSION;  // Must be "2.0"
    JSONValue id;                      // Request ID
    JSONValue result;                  // Result (exclusive with errorValue)
    JSONValue errorValue;              // Error (exclusive with result)
    
    /// Create success response
    static Response success(JSONValue id, JSONValue result) {
        Response resp;
        resp.id = id;
        resp.result = result;
        return resp;
    }
    
    /// Create error response
    static Response makeError(JSONValue id, int code, 
                            string message, string details = null) {
        Response resp;
        resp.id = id;
        resp.errorValue = JSONValue([
            "code": JSONValue(code),
            "message": JSONValue(message)
        ]);
        if (details !is null) {
            resp.errorValue["data"] = JSONValue(details);
        }
        return resp;
    }
    
    /// Convert to JSON
    JSONValue toJSON() const {
        JSONValue[string] json = [
            "jsonrpc": JSONValue(JSONRPC_VERSION),
            "id": id
        ];
        
        if (errorValue.type != JSONType.null_) {
            json["error"] = errorValue;
        } else {
            json["result"] = result;
        }
        
        return JSONValue(json);
    }
}
