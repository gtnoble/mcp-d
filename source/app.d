import std.stdio;
import std.conv : to;
import std.json;

import mcp.server;
import mcp.schema;
import mcp.resources : ResourceContents;

version(unittest) {} else
void main() {
    // Create server with custom name and version
    auto server = new MCPServer("Example MCP Server", "0.1.0");
    
    // Add a simple calculator tool
    server.addTool(
        "add",                        // Tool name
        "Add two numbers",            // Description
        SchemaBuilder.object()        // Input schema
            .addProperty("a",
                SchemaBuilder.number()
                    .setDescription("First number")
                    .range(-1000, 1000))
            .addProperty("b",
                SchemaBuilder.number()
                    .setDescription("Second number")
                    .range(-1000, 1000)),
        (JSONValue args) {  // Explicit argument type
            auto a = args["a"].get!double;
            auto b = args["b"].get!double;
            return JSONValue(a + b);
        }
    );
    
    // Add a text processing tool
    server.addTool(
        "capitalize",
        "Convert text to uppercase",
        SchemaBuilder.object()
            .addProperty("text",
                SchemaBuilder.string_()
                    .setDescription("Text to capitalize")
                    .stringLength(1, 1000)),
        (JSONValue args) {  // Explicit argument type
            import std.string : toUpper;
            return JSONValue(args["text"].str.toUpper);
        }
    );
    
    // Add a static configuration resource
    server.addResource(
        "config://version",           // Resource URI
        "Version Info",               // Name
        "Current application version", // Description
        () {
            return ResourceContents.makeText(
                "application/json",
                `{"version": "0.1.0", "built": "2025-03-26"}`
            );
        }
    );
    
    // Add a static text resource with change notification
    auto notifyGreetingChanged = server.addResource(
        "memory://greeting",
        "Greeting",
        "A friendly greeting",
        () => ResourceContents.makeText(
            "text/plain",
            "Hello, World!"
        )
    );
    
    // Start the server
    server.start();
}
