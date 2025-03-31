/**
 * Tool registration and execution for MCP.
 *
 * This module provides the functionality for registering, managing, and executing
 * tools in the MCP server. Tools are functions that can be called by AI models
 * with validated parameters.
 *
 * The module includes:
 * - Tool registry for managing available tools
 * - Tool execution with schema validation
 * - Standardized error handling and response formatting
 *
 * Example:
 * ```d
 * // Create a tool registry
 * auto registry = new ToolRegistry();
 *
 * // Define a tool schema
 * auto schema = SchemaBuilder.object()
 *     .addProperty("name", SchemaBuilder.string_())
 *     .addProperty("age", SchemaBuilder.integer().range(0, 150));
 *
 * // Define a tool handler
 * auto handler = delegate(JSONValue args) {
 *     auto name = args["name"].str;
 *     auto age = args["age"].integer;
 *     return JSONValue(["message": "Hello " ~ name ~ ", you are " ~ age.to!string ~ " years old"]);
 * };
 *
 * // Register the tool
 * registry.addTool("greet", "Greet a person", schema, handler);
 * ```
 */
module mcp.tools;

import std.json;
import mcp.schema;
import mcp.protocol : MCPError, ErrorCode;
import std.exception : assertThrown;

version(unittest) {
    import std.format : format;
}

/**
 * Tool Registry Tests
 *
 * These tests verify the functionality of the ToolRegistry class,
 * including tool registration, retrieval, and error handling.
 */
unittest {
    auto registry = new ToolRegistry();
    auto schema = SchemaBuilder.object()
        .addProperty("name", SchemaBuilder.string_());
    auto handler = delegate(JSONValue args) { return JSONValue("ok"); };

    // Test valid registration
    registry.addTool("test", "A test tool", schema, handler);
    auto tool = registry.getTool("test");
    assert(tool !is null);

    // Test duplicate registration
    assertThrown!MCPError(
        registry.addTool("test", "Duplicate tool", schema, handler)
    );

    // Test invalid registrations
    assertThrown!ToolExecutionError(
        registry.addTool("", "Empty name", schema, handler)
    );
    assertThrown!ToolExecutionError(
        registry.addTool("test2", "", schema, handler)
    );
    assertThrown!ToolExecutionError(
        registry.addTool("test3", "No schema", null, handler)
    );
    assertThrown!ToolExecutionError(
        registry.addTool("test4", "No handler", schema, null)
    );

    // Test getting non-existent tool
    assertThrown!MCPError(registry.getTool("nonexistent"));
}

/**
 * Tool Execution Tests
 *
 * These tests verify the functionality of the Tool class,
 * including schema validation and error handling during execution.
 */
unittest {
    // Create a test tool with schema validation
    auto schema = SchemaBuilder.object()
        .addProperty("name", SchemaBuilder.string_().stringLength(1, 50))
        .addProperty("age", SchemaBuilder.integer().range(0, 150))
        .addProperty("tags", SchemaBuilder.array(SchemaBuilder.string_()).optional());
    
    auto handler = delegate(JSONValue args) {
        auto name = args["name"].str;
        auto age = args["age"].integer;
        return JSONValue([
            "message": JSONValue(format("Hello %s, you are %d years old", name, age))
        ]);
    };
    
    auto tool = new Tool("test", "A test tool", schema, handler);
    
    // Test valid input
    auto validInput = JSONValue([
        "name": JSONValue("John"),
        "age": JSONValue(30)
    ]);
    auto result = tool.execute(validInput);
    assert(result.type == JSONType.object);
    assert(!("isError" in result));
    assert("content" in result);
    
    // Test invalid type
    auto invalidType = JSONValue([
        "name": JSONValue("John"),
        "age": JSONValue("30") // Wrong type for age
    ]);
    auto typeError = tool.execute(invalidType);
    assert(typeError["isError"].boolean == true);
    assert(typeError["content"][0]["text"].str.length > 0);
    
    // Test missing required field
    auto missingField = JSONValue([
        "name": JSONValue("John")
    ]);
    auto missingError = tool.execute(missingField);
    assert(missingError["isError"].boolean == true);
    assert(missingError["content"][0]["text"].str.length > 0);
    
    // Test invalid extra field
    auto extraField = JSONValue([
        "name": JSONValue("John"),
        "age": JSONValue(30),
        "extra": JSONValue("field")
    ]);
    auto extraError = tool.execute(extraField);
    assert(extraError["isError"].boolean == true);
    assert(extraError["content"][0]["text"].str.length > 0);
}

/**
 * Tool handler function type.
 *
 * This delegate type defines the signature for tool implementation functions.
 * It takes a JSONValue containing the validated arguments and returns a JSONValue result.
 */
alias ToolHandler = JSONValue delegate(JSONValue args);

/**
 * Exception thrown when tool execution fails.
 *
 * This exception is used for errors during tool registration or execution,
 * such as invalid parameters or schema validation failures.
 */
class ToolExecutionError : MCPError {
    this(string message, string details = null, 
         string file = __FILE__, size_t line = __LINE__) {
        super(ErrorCode.invalidParams, message, details, file, line);
    }
}

/**
 * Tool definition and execution.
 *
 * The Tool class represents a registered tool with its metadata and handler function.
 * It handles parameter validation against the schema and standardized response formatting.
 */
class Tool {
    private {
        string name;
        string description;
        SchemaBuilder schema;
        ToolHandler handler;
    }
    
    this(string name, string description, 
         SchemaBuilder schema, ToolHandler handler) {
        this.name = name;
        this.description = description;
        this.schema = schema;
        this.handler = handler;
    }
    
    /**
     * Converts the tool definition to JSON format.
     *
     * This method generates the tool metadata in the format specified by the MCP protocol.
     *
     * Returns:
     *   A JSONValue containing the tool's name, description, and input schema
     */
    JSONValue toJSON() const {
        return JSONValue([
            "name": JSONValue(name),
            "description": JSONValue(description),
            "inputSchema": schema.toJSON()
        ]);
    }
    
    /**
     * Executes the tool with the provided arguments.
     *
     * This method validates the arguments against the schema, calls the handler function,
     * and formats the response according to the MCP protocol.
     *
     * Params:
     *   args = The arguments to pass to the tool handler
     *
     * Returns:
     *   A JSONValue containing the tool's response in the standard format
     *   If execution fails, returns an error response with isError=true
     */
    JSONValue execute(JSONValue args) {
        try {
            // Validate arguments against schema
            try {
                schema.validate(args);
            } catch (SchemaValidationError e) {
                throw new ToolExecutionError(e.msg);
            }
            
            // Call handler with validated arguments
            auto result = handler(args);
            
            // If result is already an object with _meta or content, return as-is
            if (result.type == JSONType.object) {
                if ("_meta" in result || "content" in result) {
                    return result;
                }
            }
            
            // Otherwise wrap in standard format
            return JSONValue([
                "content": JSONValue([
                    JSONValue([
                        "type": JSONValue("text"),
                        "text": JSONValue(result.toString())
                    ])
                ])
            ]);
        }
        catch (Exception e) {
            // Wrap errors in standard format
            return JSONValue([
                "content": JSONValue([
                    JSONValue([
                        "type": JSONValue("text"),
                        "text": JSONValue(e.msg)
                    ])
                ]),
                "isError": JSONValue(true)
            ]);
        }
    }
}

/**
 * Registry for managing available tools.
 *
 * The ToolRegistry class provides methods for registering, retrieving,
 * and listing tools available in the MCP server.
 */
class ToolRegistry {
    private Tool[string] tools;
    
    /**
     * Registers a new tool with the registry.
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
        if (name.length == 0) {
            throw new ToolExecutionError("Tool name cannot be empty");
        }
        if (description.length == 0) {
            throw new ToolExecutionError("Tool description cannot be empty");
        }
        if (schema is null) {
            throw new ToolExecutionError("Tool schema cannot be null");
        }
        if (handler is null) {
            throw new ToolExecutionError("Tool handler cannot be null");
        }
        if (name in tools) {
            throw new MCPError(
                ErrorCode.invalidRequest,
                "Tool already exists: " ~ name
            );
        }
        tools[name] = new Tool(name, description, schema, handler);
    }
    
    /**
     * Retrieves a tool by name.
     *
     * Params:
     *   name = The name of the tool to retrieve
     *
     * Returns:
     *   The requested Tool object
     *
     * Throws:
     *   MCPError if the tool does not exist
     */
    Tool getTool(string name) {
        auto tool = name in tools;
        if (tool is null) {
            throw new MCPError(
                ErrorCode.methodNotFound,
                "Tool not found: " ~ name
            );
        }
        return *tool;
    }
    
    /**
     * Lists all available tools.
     *
     * Returns:
     *   A JSONValue containing an array of tool definitions
     *   in the format specified by the MCP protocol
     */
    JSONValue listTools() {
        import std.algorithm : map;
        import std.array : array;
        
        auto toolArray = tools.values
            .map!(t => t.toJSON())
            .array;
        
        return JSONValue([
            "tools": JSONValue(toolArray)
        ]);
    }
}
