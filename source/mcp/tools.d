module mcp.tools;

import std.json;
import mcp.schema;
import mcp.protocol : MCPError, ErrorCode;
import std.exception : assertThrown;

version(unittest) {
    import std.format : format;
}

// Tool Registry Tests
unittest {
    auto registry = new ToolRegistry();
    auto schema = SchemaBuilder.object()
        .addProperty("name", SchemaBuilder.string_());
    auto handler = (JSONValue args) { return JSONValue("ok"); };

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

// Tool Execution Tests
unittest {
    // Create a test tool with schema validation
    auto schema = SchemaBuilder.object()
        .addProperty("name", SchemaBuilder.string_().stringLength(1, 50))
        .addProperty("age", SchemaBuilder.integer().range(0, 150))
        .addProperty("tags", SchemaBuilder.array(SchemaBuilder.string_()).optional());
    
    auto handler = (JSONValue args) {
        auto name = args["name"].str;
        auto age = args["age"].integer;
        return JSONValue([
            "message": JSONValue(format("Hello %s, you are %d years old", name, age))
        ]);
    };
    
    auto tool = new Tool("test", "A test tool", schema, handler);
    
    // Test valid input
    auto validInput = JSONValue([
        "name": "John",
        "age": 30
    ]);
    auto result = tool.execute(validInput);
    assert(result.type == JSONType.object);
    assert(!("isError" in result));
    assert("content" in result);
    
    // Test invalid type
    auto invalidType = JSONValue([
        "name": "John",
        "age": "30" // Wrong type for age
    ]);
    auto typeError = tool.execute(invalidType);
    assert(typeError["isError"].boolean == true);
    assert(typeError["content"][0]["text"].str.length > 0);
    
    // Test missing required field
    auto missingField = JSONValue([
        "name": "John"
    ]);
    auto missingError = tool.execute(missingField);
    assert(missingError["isError"].boolean == true);
    assert(missingError["content"][0]["text"].str.length > 0);
    
    // Test invalid extra field
    auto extraField = JSONValue([
        "name": "John",
        "age": 30,
        "extra": "field"
    ]);
    auto extraError = tool.execute(extraField);
    assert(extraError["isError"].boolean == true);
    assert(extraError["content"][0]["text"].str.length > 0);
}

/// Tool handler type
alias ToolHandler = JSONValue delegate(JSONValue args);

/// Tool execution error
class ToolExecutionError : MCPError {
    this(string message, string details = null, 
         string file = __FILE__, size_t line = __LINE__) {
        super(ErrorCode.invalidParams, message, details, file, line);
    }
}

/// Tool definition
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
    
    /// Get tool metadata as JSON
    JSONValue toJSON() const {
        return JSONValue([
            "name": JSONValue(name),
            "description": JSONValue(description),
            "inputSchema": schema.toJSON()
        ]);
    }
    
    /// Execute tool with given arguments
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

/// Tool registry
class ToolRegistry {
    private Tool[string] tools;
    
    /// Add tool
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
    
    /// Get tool by name
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
    
    /// List available tools
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
