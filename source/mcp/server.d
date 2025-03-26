module mcp.server;

import std.json;
import std.algorithm : startsWith;

import mcp.protocol;
import mcp.schema;
import mcp.tools;
import mcp.resources;
import mcp.transport.stdio;

/// MCP server implementation
class MCPServer {
    private {
        ToolRegistry toolRegistry;
        ResourceRegistry resourceRegistry;
        Transport transport;
        bool initialized;
        ServerInfo serverInfo;
        ServerCapabilities capabilities;
    }
    
    this(string name = "D MCP Server", string version_ = "1.0.0") {
        toolRegistry = new ToolRegistry();
        
        // Set up resource registry with notification handler
        resourceRegistry = new ResourceRegistry((string uri) {
            // Send resource updated notification
            if (transport && capabilities.resources.listChanged) {
                transport.sendMessage(JSONValue([
                    "jsonrpc": JSONValue(JSONRPC_VERSION),
                    "method": JSONValue("notifications/resources/updated"),
                    "params": JSONValue(["uri": JSONValue(uri)])
                ]));
            }
        });
        
        // Initialize server info and capabilities
        serverInfo = ServerInfo(name, version_);
        capabilities = ServerCapabilities(
            ResourceCapabilities(true, false),  // listChanged=true, subscribe=false
            ToolCapabilities(true)              // listChanged=true
        );
    }
    
    /// Add tool
    void addTool(string name, string description,
                 SchemaBuilder schema, ToolHandler handler) {
        toolRegistry.addTool(name, description, schema, handler);
    }
    
    /// Add static resource
    ResourceNotifier addResource(string uri, string name,
                               string description,
                               StaticResourceReader reader) {
        return resourceRegistry.addResource(
            uri, name, description, reader
        );
    }
    
    /// Add dynamic resource
    ResourceNotifier addDynamicResource(string baseUri, string name,
                                      string description,
                                      DynamicResourceReader reader) {
        return resourceRegistry.addDynamicResource(
            baseUri, name, description, reader
        );
    }
    
    /// Start server with stdio transport
    void start() {
        transport = createStdioTransport(&handleMessage);
        transport.run();
    }
    
    /// Handle incoming message
    private void handleMessage(JSONValue message) {
        try {
            auto request = Request.fromJSON(message);
            
            // Handle request
            if (!request.isNotification()) {
                JSONValue response;
                
                try {
                    // Check initialization
                    if (!initialized && request.method != "initialize") {
                        throw new MCPError(
                            ErrorCode.invalidRequest,
                            "Server not initialized"
                        );
                    }
                    
                    // Handle method
                    response = handleRequest(request);
                }
                catch (MCPError e) {
                    // Protocol error
                    response = Response.makeError(
                        request.id,
                        e.code,
                        e.msg,
                        e.details
                    ).toJSON();
                }
                catch (Exception e) {
                    // Internal error
                    response = Response.makeError(
                        request.id,
                        ErrorCode.internalError,
                        "Internal error: " ~ e.msg
                    ).toJSON();
                }
                
                transport.sendMessage(response);
            }
            else {
                // Handle notification
                handleNotification(request);
            }
        }
        catch (Exception e) {
            // Invalid request
            if (!message.type == JSONType.object || "id" !in message) {
                transport.sendMessage(Response.makeError(
                    JSONValue(null),
                    ErrorCode.invalidRequest,
                    "Invalid request: " ~ e.msg
                ).toJSON());
            }
            else {
                transport.sendMessage(Response.makeError(
                    message["id"],
                    ErrorCode.invalidRequest,
                    "Invalid request: " ~ e.msg
                ).toJSON());
            }
        }
    }
    
    /// Handle request
    private JSONValue handleRequest(Request request) {
        // Initialize request
        if (request.method == "initialize") {
            initialized = true;
            return Response.success(request.id, JSONValue([
                "protocolVersion": JSONValue(PROTOCOL_VERSION),
                "capabilities": capabilities.toJSON(),
                "serverInfo": serverInfo.toJSON()
            ])).toJSON();
        }
        
        // Tool methods
        if (request.method == "tools/list") {
            return Response.success(
                request.id,
                toolRegistry.listTools()
            ).toJSON();
        }
        
        if (request.method == "tools/call") {
            auto params = request.params;
            if ("name" !in params || "arguments" !in params) {
                throw new MCPError(
                    ErrorCode.invalidParams,
                    "Missing tool name or arguments"
                );
            }
            
            auto tool = toolRegistry.getTool(params["name"].str);
            auto result = tool.execute(params["arguments"]);
            
            return Response.success(request.id, result).toJSON();
        }
        
        // Resource methods
        if (request.method == "resources/list") {
            return Response.success(
                request.id,
                resourceRegistry.listResources()
            ).toJSON();
        }
        
        if (request.method == "resources/read") {
            auto params = request.params;
            if ("uri" !in params) {
                throw new MCPError(
                    ErrorCode.invalidParams,
                    "Missing resource URI"
                );
            }
            
            auto contents = resourceRegistry.readResource(
                params["uri"].str
            );
            
            return Response.success(request.id, JSONValue([
                "contents": [contents.toJSON()]
            ])).toJSON();
        }
        
        // Unknown method
        throw new MCPError(
            ErrorCode.methodNotFound,
            "Method not found: " ~ request.method
        );
    }
    
    /// Handle notification
    private void handleNotification(Request notification) {
        // Only handle initialized notification for now
        if (notification.method == "notifications/initialized") {
            // Nothing to do
            return;
        }
    }
}

/// Server capabilities
private struct ServerCapabilities {
    ResourceCapabilities resources;
    ToolCapabilities tools;
    
    JSONValue toJSON() const {
        return JSONValue([
            "resources": resources.toJSON(),
            "tools": tools.toJSON()
        ]);
    }
}

private struct ResourceCapabilities {
    bool listChanged;
    bool subscribe;
    
    JSONValue toJSON() const {
        return JSONValue([
            "listChanged": JSONValue(listChanged),
            "subscribe": JSONValue(subscribe)
        ]);
    }
}

private struct ToolCapabilities {
    bool listChanged;
    
    JSONValue toJSON() const {
        return JSONValue([
            "listChanged": JSONValue(listChanged)
        ]);
    }
}

private struct ServerInfo {
    string name;
    string version_;
    
    this(string name, string version_) {
        this.name = name;
        this.version_ = version_;
    }
    
    JSONValue toJSON() const {
        return JSONValue([
            "name": JSONValue(name),
            "version": JSONValue(version_)
        ]);
    }
}
