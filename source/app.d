import std.stdio;
import std.conv : to;
import std.json;
import std.base64;

import mcp.server;
import mcp.schema;
import mcp.resources : ResourceContents;
import mcp.prompts;

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
    
    // Add example prompts
    
    // 1. Simple text prompt
    server.addPrompt(
        "greet",
        "A friendly greeting prompt",
        [
            PromptArgument("name", "User's name", true),
            PromptArgument("language", "Language code (en/es)", false)
        ],
        (string name, string[string] args) {
            string greeting = "language" in args && args["language"] == "es" ?
                "¡Hola" : "Hello";
            
            return PromptResponse(
                "Greeting response",
                [PromptMessage.text("assistant", greeting ~ " " ~ args["name"] ~ "!")]
            );
        }
    );
    
    // 2. Multi-modal prompt with image
    server.addPrompt(
        "image_badge",
        "Generate a user badge with avatar",
        [
            PromptArgument("username", "Username to display", true),
            PromptArgument("role", "User role (admin/user)", true)
        ],
        (string name, string[string] args) {
            // Example base64 encoded 1x1 pixel PNG
            auto imageData = 
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==";
            
            return PromptResponse(
                "User badge for " ~ args["username"],
                [
                    PromptMessage.text(
                        "assistant",
                        "User Badge for " ~ args["username"] ~ " (" ~ args["role"] ~ ")"
                    ),
                    PromptMessage.image(
                        "assistant",
                        imageData,
                        "image/png"
                    )
                ]
            );
        }
    );
    
    // 3. Prompt with embedded resource
    server.addPrompt(
        "system_info",
        "Show system information",
        [],  // No arguments needed
        (string name, string[string] args) {
            return PromptResponse(
                "System information",
                [
                    PromptMessage.text(
                        "assistant",
                        "Here's the current system information:"
                    ),
                    // Pass content directly to match the resource message format
                    PromptMessage.resource(
                        "assistant",
                        "config://version",
                        "application/json",
                        `{"version": "0.1.0", "built": "2025-03-26"}`
                    )
                ]
            );
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
    
    // Add a weather forecast template resource
    server.addTemplate(
        "weather://{city}/{date}",       // URI template
        "Weather Forecast",              // Name
        "Get weather forecast for a specific city and date", // Description
        "application/json",              // MIME type
        (params) {
            // Validate required parameters
            assert("city" in params && "date" in params);
            
            // Generate mock weather data
            auto forecast = JSONValue([
                "city": JSONValue(params["city"]),
                "date": JSONValue(params["date"]),
                "temperature": JSONValue(72),
                "conditions": JSONValue("sunny"),
                "humidity": JSONValue(45),
                "windSpeed": JSONValue(8)
            ]);
            
            return ResourceContents.makeText(
                "application/json",
                forecast.toString()
            );
        }
    );
    
    // Start the server
    server.start();
}
