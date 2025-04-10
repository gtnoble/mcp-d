/**
 * Model Context Protocol (MCP) server implementation.
 *
 * This module provides the core server implementation for the MCP protocol,
 * handling message processing, tool registration, resource management, and
 * prompt handling. The server implements the MCP specification v2024-11-05.
 *
 * The MCPServer class serves as the main entry point for applications wanting
 * to provide functionality to AI language models through the MCP protocol.
 *
 * Example:
 * ```d
 * // Create a server with default stdio transport
 * auto server = new MCPServer("My MCP Server", "1.0.0");
 * 
 * // Add a simple tool
 * server.addTool(
 *     "greet",
 *     "Greet a user by name",
 *     SchemaBuilder.object()
 *         .addProperty("name", SchemaBuilder.string_()),
 *     (args) {
 *         return JSONValue(["greeting": "Hello, " ~ args["name"].str]);
 *     }
 * );
 * 
 * // Start the server
 * server.start();
 * ```
 */
module mcp.server;

import std.json;
import std.algorithm : startsWith;

import mcp.protocol;
import mcp.schema;
import mcp.tools;
import mcp.resources;
import mcp.prompts;
import mcp.transport.stdio;

/**
 * MCP server implementation.
 *
 * The MCPServer class provides a complete implementation of the Model Context
 * Protocol server, handling message processing, tool registration, resource
 * management, and prompt handling.
 */
class MCPServer {
    private {
        ToolRegistry toolRegistry;         /// Registry for tools
        ResourceRegistry resourceRegistry; /// Registry for resources
        PromptRegistry promptRegistry;     /// Registry for prompts
        Transport transport;               /// Transport layer for communication
        bool initialized;                  /// Whether the server has been initialized
        ServerInfo serverInfo;             /// Server information
        ServerCapabilities capabilities;   /// Server capabilities
    }
    
    /**
     * Constructs an MCPServer with the specified transport.
     *
     * This constructor allows providing a custom transport implementation.
     *
     * Params:
     *   transport = The transport layer to use for communication
     *   name = The server name to report in initialization
     *   version_ = The server version to report in initialization
     */
    this(Transport transport, string name = "D MCP Server", string version_ = "1.0.0") {
        this.transport = transport;
        transport.setMessageHandler(&handleMessage);
        toolRegistry = new ToolRegistry();
        
        // Set up prompt registry with notification handler
        promptRegistry = new PromptRegistry((string name) {
            if (transport && capabilities.prompts.listChanged) {
                transport.sendMessage(JSONValue([
                    "jsonrpc": JSONValue(JSONRPC_VERSION),
                    "method": JSONValue("notifications/prompts/list_changed")
                ]));
            }
        });
        
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
            ToolCapabilities(true),            // listChanged=true
            PromptCapabilities(true)           // listChanged=true
        );
    }

    /**
     * Constructs an MCPServer with the default stdio transport.
     *
     * This constructor creates a server using the standard input/output
     * for communication, which is the most common transport for MCP.
     *
     * Params:
     *   name = The server name to report in initialization
     *   version_ = The server version to report in initialization
     */
    this(string name = "D MCP Server", string version_ = "1.0.0") {
        auto transport = createStdioTransport();
        transport.setMessageHandler(&handleMessage);
        this(transport, name, version_);
    }
    
    /**
     * Executes a registered tool by name with provided arguments.
     *
     * This method provides direct access to tool execution without going through
     * the JSON-RPC protocol layer.
     *
     * Params:
     *   name = The name of the tool to execute
     *   arguments = The arguments to pass to the tool
     *
     * Returns:
     *   The tool's execution result as a JSONValue
     *
     * Throws:
     *   MCPError if the tool does not exist
     *   ToolExecutionError if arguments are invalid
     */
    JSONValue executeTool(string name, JSONValue arguments) {
        auto tool = toolRegistry.getTool(name);
        return tool.execute(arguments);
    }
    
    /**
     * Registers a tool with the server.
     *
     * Tools provide functionality that can be invoked by AI models.
     *
     * Params:
     *   name = The tool name (must be unique)
     *   description = Human-readable description of the tool
     *   schema = Input schema defining the tool's parameters
     *   handler = Function to execute when the tool is called
     *
     * Throws:
     *   MCPError if a tool with the same name already exists
     *   ToolExecutionError if any parameters are invalid
     */
    void addTool(string name, string description,
                 SchemaBuilder schema, ToolHandler handler) {
        toolRegistry.addTool(name, description, schema, handler);
    }
    
    /**
     * Registers a prompt with the server.
     *
     * Prompts provide pre-defined message templates that can be used by AI models.
     *
     * Params:
     *   name = The prompt name (must be unique)
     *   description = Human-readable description of the prompt
     *   arguments = Array of arguments the prompt accepts
     *   handler = Function to generate prompt content when requested
     *
     * Throws:
     *   MCPError if a prompt with the same name already exists
     */
    void addPrompt(string name, string description,
                  PromptArgument[] arguments,
                  PromptResponse delegate(string, string[string]) handler) {
        promptRegistry.addPrompt(
            Prompt(name, description, arguments),
            handler  // Type matches PromptHandler alias
        );
    }
    
    /**
     * Adds a static resource to the server.
     *
     * Static resources have fixed content that doesn't change based on the path.
     *
     * Params:
     *   uri = The URI that identifies this resource
     *   name = Human-readable name for the resource
     *   description = Human-readable description
     *   reader = Function that provides the resource content
     *
     * Returns:
     *   A notifier function that can be called to signal resource changes
     */
    ResourceNotifier addResource(string uri, string name,
                               string description,
                               StaticResourceReader reader) {
        return resourceRegistry.addResource(
            uri, name, description, reader
        );
    }
    
    /**
     * Adds a dynamic resource to the server.
     *
     * Dynamic resources have content that varies based on the path after the base URI.
     *
     * Params:
     *   baseUri = The base URI prefix for this resource
     *   name = Human-readable name for the resource
     *   description = Human-readable description
     *   reader = Function that provides the resource content based on the path
     *
     * Returns:
     *   A notifier function that can be called to signal resource changes
     */
    ResourceNotifier addDynamicResource(string baseUri, string name,
                                      string description,
                                      DynamicResourceReader reader) {
        return resourceRegistry.addDynamicResource(
            baseUri, name, description, reader
        );
    }

    /**
     * Adds a resource template to the server.
     *
     * Resource templates allow parameterized URIs with variable substitution.
     *
     * Params:
     *   uriTemplate = The URI template with parameters in {braces}
     *   name = Human-readable name for the template
     *   description = Human-readable description
     *   mimeType = The MIME type of the resource
     *   reader = Function that provides content based on extracted parameters
     *
     * Returns:
     *   A notifier function that can be called to signal template changes
     */
    ResourceNotifier addTemplate(string uriTemplate, string name,
                               string description, string mimeType,
                               ResourceContents delegate(string[string]) reader) {
        return resourceRegistry.addTemplate(
            uriTemplate, name, description, mimeType, reader
        );
    }
    
    /**
     * Starts the server and begins processing messages.
     *
     * This method starts the transport layer and begins handling incoming messages.
     * It typically blocks until the transport is closed.
     */
    void start() {
        transport.run();
    }
    
    /**
     * Handles an incoming message from the transport.
     *
     * This method processes JSON-RPC requests and notifications according to
     * the MCP protocol specification.
     *
     * Params:
     *   message = The JSON message to process
     */
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
    
    /**
     * Processes a JSON-RPC request and generates a response.
     *
     * This method handles all the standard MCP methods including initialization,
     * tool calls, resource access, and prompt retrieval.
     *
     * Params:
     *   request = The parsed request object
     *
     * Returns:
     *   A JSON response to send back to the client
     *
     * Throws:
     *   MCPError for protocol-level errors
     */
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
        
        // Ping method
        if (request.method == "ping") {
            return Response.success(request.id, JSONValue.emptyObject).toJSON();
        }

        // Tool methods
        if (request.method == "prompts/list") {
            return Response.success(request.id, promptRegistry.listPrompts()).toJSON();
        }

        if (request.method == "prompts/get") {
            auto params = request.params;
            if ("name" !in params) {
                throw new MCPError(
                    ErrorCode.invalidParams,
                    "Missing prompt name"
                );
            }
            auto name = params["name"].str;
            auto result = promptRegistry.getPromptContent(name, params);
            return Response.success(request.id, result).toJSON();
        }
        
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
        
        if (request.method == "resources/templates/list") {
            return Response.success(
                request.id,
                resourceRegistry.listTemplates()
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
    
    /**
     * Processes a JSON-RPC notification.
     *
     * Notifications are one-way messages that don't require a response.
     *
     * Params:
     *   notification = The parsed notification object
     */
    private void handleNotification(Request notification) {
        // Only handle initialized notification for now
        if (notification.method == "notifications/initialized") {
            // Nothing to do
            return;
        }
    }
}

/**
 * Server capabilities reported during initialization.
 *
 * This structure defines the capabilities of the server according to
 * the MCP specification.
 */
private struct ServerCapabilities {
    ResourceCapabilities resources;
    ToolCapabilities tools;
    PromptCapabilities prompts;
    
    JSONValue toJSON() const {
        return JSONValue([
            "resources": resources.toJSON(),
            "tools": tools.toJSON(),
            "prompts": prompts.toJSON()
        ]);
    }
}

/**
 * Resource-specific capabilities.
 */
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

/**
 * Tool-specific capabilities.
 */
private struct ToolCapabilities {
    bool listChanged;
    
    JSONValue toJSON() const {
        return JSONValue([
            "listChanged": JSONValue(listChanged)
        ]);
    }
}

/**
 * Prompt-specific capabilities.
 */
private struct PromptCapabilities {
    bool listChanged;
    
    JSONValue toJSON() const {
        return JSONValue([
            "listChanged": JSONValue(listChanged)
        ]);
    }
}

/**
 * Server information reported during initialization.
 */
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
