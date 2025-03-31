/**
 * MCP protocol definitions and JSON-RPC implementation.
 *
 * This module provides the core protocol types and utilities for the MCP
 * implementation, including JSON-RPC request/response handling, error codes,
 * and protocol constants.
 *
 * The module includes:
 * - Protocol version constants
 * - JSON-RPC error codes
 * - Request and Response structures
 * - Error handling
 */
module mcp.protocol;

import std.json;

/**
 * Protocol version supported by this implementation.
 *
 * This constant defines the MCP protocol version implemented by this library.
 */
const string PROTOCOL_VERSION = "2024-11-05";

/**
 * JSON-RPC version used by MCP.
 *
 * This constant defines the JSON-RPC version used for message formatting.
 */
const string JSONRPC_VERSION = "2.0";

/**
 * Standard JSON-RPC error codes.
 *
 * These error codes are defined by the JSON-RPC 2.0 specification and
 * are used for protocol-level errors.
 */
enum ErrorCode {
    parseError = -32700,        // Invalid JSON
    invalidRequest = -32600,    // Not a valid request object
    methodNotFound = -32601,    // Method not found
    invalidParams = -32602,     // Invalid method parameters
    internalError = -32603      // Internal server error
}

/**
 * Base MCP error exception.
 *
 * This exception class is used for all protocol-level errors in the MCP
 * implementation. It includes an error code, message, and optional details.
 */
class MCPError : Exception {
    int code;
    string details;
    
    this(int code, string message, string details = null, 
         string file = __FILE__, size_t line = __LINE__) {
        this.code = code;
        this.details = details;
        super(message, file, line);
    }
    
    /**
     * Converts the error to a JSON-RPC error response.
     *
     * Returns:
     *   A JSONValue containing the error in JSON-RPC format
     */
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

/**
 * JSON-RPC request structure.
 *
 * This structure represents a JSON-RPC request, which can be either
 * a method call (with ID) or a notification (without ID).
 */
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
    
    /**
     * Creates a Request from a JSON value.
     *
     * This method parses and validates a JSON-RPC request.
     *
     * Params:
     *   json = The JSON value to parse
     *
     * Returns:
     *   A Request object
     *
     * Throws:
     *   MCPError if the JSON is not a valid JSON-RPC request
     */
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
    
    /**
     * Converts the request to JSON format.
     *
     * Returns:
     *   A JSONValue containing the request in JSON-RPC format
     */
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
    
    /**
     * Checks if this request is a notification.
     *
     * Notifications are requests without an ID, which do not
     * require a response.
     *
     * Returns:
     *   true if this is a notification, false otherwise
     */
    bool isNotification() const {
        return id.type == JSONType.null_;
    }
}

/**
 * JSON-RPC response structure.
 *
 * This structure represents a JSON-RPC response, which can be either
 * a success response (with result) or an error response (with error).
 */
struct Response {
    string jsonrpc = JSONRPC_VERSION;  // Must be "2.0"
    JSONValue id;                      // Request ID
    JSONValue result;                  // Result (exclusive with errorValue)
    JSONValue errorValue;              // Error (exclusive with result)
    
    /**
     * Creates a success response.
     *
     * Params:
     *   id = The request ID
     *   result = The result value
     *
     * Returns:
     *   A Response object with the result
     */
    static Response success(JSONValue id, JSONValue result) {
        Response resp;
        resp.id = id;
        resp.result = result;
        return resp;
    }
    
    /**
     * Creates an error response.
     *
     * Params:
     *   id = The request ID
     *   code = The error code
     *   message = The error message
     *   details = Optional error details
     *
     * Returns:
     *   A Response object with the error
     */
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
    
    /**
     * Converts the response to JSON format.
     *
     * Returns:
     *   A JSONValue containing the response in JSON-RPC format
     */
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
