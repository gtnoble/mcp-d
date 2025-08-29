/**
 * Example MCP server application.
 *
 * This module demonstrates how to use the D MCP Server library to create
 * a fully functional MCP server with tools, resources, and prompts.
 *
 * The example includes:
 * - Setting up an MCP server with custom name and version
 * - Registering tools with schema validation
 * - Creating various types of prompts (text, image, resource)
 * - Adding static and template-based resources
 * - Implementing change notifications
 *
 * This can be used as a reference implementation for creating your own
 * MCP servers with the library.
 */
import std.stdio;
import std.conv : to;
import std.json;
import std.base64;
import std.getopt;

import mcp.server;
import mcp.schema;
import mcp.resources : ResourceContents;
import mcp.prompts;
import mcp.transport.http : createHttpTransport;

// Create shared state for resources
__gshared {
    int counter = 0;
    long lastUpdateTime = 0;
    int requestCount = 0;
}

version(unittest) {} else
/**
 * Main entry point for the example MCP server.
 *
 * This function creates and configures an MCP server with example
 * tools, prompts, and resources, then starts it.
 */
void main(string[] args) {
    string transportType = "stdio";
    string host = "127.0.0.1";
    ushort port = 8080;
    getopt(args, "transport", &transportType, "host", &host, "port", &port);

    MCPServer server;
    if (transportType == "http") {
        auto transport = createHttpTransport(host, port);
        server = new MCPServer(transport, "Example MCP Server", "0.1.0");
    } else {
        server = new MCPServer("Example MCP Server", "0.1.0");
    }

    /**
     * Example 1: Simple calculator tool with numeric validation
     *
     * This example demonstrates:
     * - Creating a tool with a descriptive name and description
     * - Defining a schema with numeric properties and constraints
     * - Implementing a handler function that processes the arguments
     * - Returning a simple JSON result
     *
     * The schema validates that:
     * - Both 'a' and 'b' are numbers
     * - Both values are within the range -1000 to 1000
     */
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
    
    /**
     * Example 2: Text processing tool with string validation
     *
     * This example demonstrates:
     * - Creating a tool that processes text input
     * - Defining a schema with string properties and constraints
     * - Using string length validation
     * - Importing and using standard library functions in handlers
     *
     * The schema validates that:
     * - The 'text' property is a string
     * - The string length is between 1 and 1000 characters
     */
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
    
    /**
     * Example prompts section
     *
     * The following examples demonstrate different types of prompts
     * that can be registered with the MCP server.
     */
    
    /**
     * Example 3: Simple text prompt with language selection
     *
     * This example demonstrates:
     * - Creating a prompt with required and optional arguments
     * - Implementing conditional logic based on arguments
     * - Returning a text-only response
     *
     * The prompt accepts:
     * - 'name' (required): The user's name to include in the greeting
     * - 'language' (optional): Language code for localization (en/es)
     */
    server.addPrompt(
        "greet",
        "A friendly greeting prompt",
        [
            PromptArgument("name", "User's name", true),
            PromptArgument("language", "Language code (en/es)", false)
        ],
        (string name, string[string] args) {
            // Conditional logic based on the optional language argument
            string greeting = "language" in args && args["language"] == "es" ?
                "¡Hola" : "Hello";
            
            return PromptResponse(
                "Greeting response",
                [PromptMessage.text("assistant", greeting ~ " " ~ args["name"] ~ "!")]
            );
        }
    );
    
    /**
     * Example 4: Multi-modal prompt with text and image content
     *
     * This example demonstrates:
     * - Creating a prompt that returns multiple content types
     * - Including both text and image content in a response
     * - Using base64-encoded image data
     *
     * The prompt accepts:
     * - 'username' (required): The username to display on the badge
     * - 'role' (required): The user's role (admin/user)
     */
    server.addPrompt(
        "image_badge",
        "Generate a user badge with avatar",
        [
            PromptArgument("username", "Username to display", true),
            PromptArgument("role", "User role (admin/user)", true)
        ],
        (string name, string[string] args) {
            // Example base64 encoded 1x1 pixel PNG
            // In a real application, this would be a dynamically generated image
            auto imageData = 
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==";
            
            return PromptResponse(
                "User badge for " ~ args["username"],
                [
                    // First message: Text content
                    PromptMessage.text(
                        "assistant",
                        "User Badge for " ~ args["username"] ~ " (" ~ args["role"] ~ ")"
                    ),
                    // Second message: Image content
                    PromptMessage.image(
                        "assistant",
                        imageData,
                        "image/png"
                    )
                ]
            );
        }
    );
    
    /**
     * Example 5: Prompt with embedded resource reference
     *
     * This example demonstrates:
     * - Creating a prompt that references resources
     * - Including resource content in a response
     * - Combining text and resource messages
     *
     * This prompt has no arguments and always returns the same content.
     */
    server.addPrompt(
        "system_info",
        "Show system information",
        [],  // No arguments needed
        (string name, string[string] args) {
            return PromptResponse(
                "System information",
                [
                    // First message: Text introduction
                    PromptMessage.text(
                        "assistant",
                        "Here's the current system information:"
                    ),
                    // Second message: Resource reference with inline content
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
    
    /**
     * Example 6: Static configuration resource with JSON content
     *
     * This example demonstrates:
     * - Creating a static resource with fixed content
     * - Using a custom URI scheme (config://)
     * - Returning JSON content with a specific MIME type
     *
     * Static resources always return the same content when accessed.
     */
    server.addResource(
        "config://version",           // Resource URI
        "Version Info",               // Name
        "Current application version", // Description
        () {
            return ResourceContents.makeText(
                "application/json",
                `{"version": "0.1.0", "built": "2025-03-31"}`
            );
        }
    );
    
    /**
     * Example 7: Auto-updating server status resource
     *
     * This example demonstrates:
     * - Creating a resource that updates automatically
     * - Using timers to trigger periodic updates
     * - Sending change notifications when content changes
     */
    import core.thread;
    import core.time;
    import std.datetime.systime;

    // Add server status resource
    auto notifyStatusChanged = server.addResource(
        "status://server",
        "Server Status",
        "Current server metrics and status",
        () {
            auto currentTime = Clock.currTime();
            requestCount++;
            
            auto status = JSONValue([
                "timestamp": JSONValue(currentTime.toISOExtString()),
                "uptime": JSONValue((currentTime.toUnixTime() - lastUpdateTime)),
                "requests": JSONValue(requestCount)
            ]);

            return ResourceContents.makeText(
                "application/json",
                status.toString()
            );
        }
    );

    /**
     * Example 8: Interactive counter with change notification
     * 
     * This example demonstrates:
     * - Resource modification through tool calls
     * - Change notifications triggered by updates
     * - Combining tools and resources
     */
    
    // Add counter resource
    auto notifyCounterChanged = server.addResource(
        "counter://value",
        "Counter Value",
        "An incrementing counter that can be modified",
        () => ResourceContents.makeText(
            "application/json",
            JSONValue(["value": JSONValue(counter)]).toString()
        )
    );

    // Add tool to increment counter
    server.addTool(
        "incrementCounter",
        "Increment the counter value",
        SchemaBuilder.object()
            .addProperty("amount",
                SchemaBuilder.number()
                    .setDescription("Amount to increment by")
                    .range(1, 100)),
        (JSONValue args) {
            auto amount = "amount" in args ? args["amount"].get!int : 1;
            counter += amount;
            notifyCounterChanged(); // Trigger notification
            return JSONValue(["newValue": JSONValue(counter)]);
        }
    );
    
    /**
     * Example 9: Template resource with parameter extraction
     *
     * This example demonstrates:
     * - Creating a resource template with parameters
     * - Extracting parameters from the URI
     * - Generating dynamic content based on parameters
     *
     * Template resources use URI templates with parameters in {braces}.
     * When a client requests a URI that matches the template, the
     * parameters are extracted and passed to the reader function.
     */
    server.addTemplate(
        "weather://{city}/{date}",       // URI template
        "Weather Forecast",              // Name
        "Get weather forecast for a specific city and date", // Description
        "application/json",              // MIME type
        (params) {
            // Validate required parameters
            assert("city" in params && "date" in params);
            
            // Generate mock weather data based on the parameters
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

    // Start update thread
    new Thread({
        while (true) {
            if (lastUpdateTime == 0) {
                lastUpdateTime = Clock.currTime().toUnixTime();
            }
            notifyStatusChanged(); // Trigger notification
            Thread.sleep(5.seconds);
        }
    }).start();

    
    /**
     * Start the server and begin processing messages.
     *
     * This method starts the transport layer and begins handling
     * incoming messages. It will block until the input stream is closed.
     */
    server.start();
}
