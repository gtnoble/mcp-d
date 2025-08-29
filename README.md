# D MCP Server Library

A D language implementation of the Model Context Protocol (MCP) server, focusing on stdio transport. This library enables D applications to provide functionality to AI language models through a standardized protocol.

## Features

- MCP protocol v2024-11-05 support
- stdio transport implementation
- HTTP transport with Server-Sent Events support
- Type-safe schema builder for tool parameters
- Resource system with static, dynamic, and template resources
- Prompt system with text, image, and resource content
- Change notifications for resources and prompts
- Clean, non-reflective design with type-safe APIs

## Installation

Add to your `dub.json`:
```json
{
    "dependencies": {
        "mcp": "~>0.1.0"
    }
}
```

## Usage

See the [example application](source/app.d) for a complete working example.

### Basic Server Setup

```d
import mcp.server;
import mcp.schema;
import std.json;

void main() {
    // Create server with default stdio transport
    auto server = new MCPServer("My MCP Server", "1.0.0");
    
    // Add a tool
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
        (JSONValue args) {            // Tool handler
            auto a = args["a"].get!double;
            auto b = args["b"].get!double;
            return JSONValue(a + b);
        }
    );
    
    // Start server and begin processing messages
    server.start();
}
```

### Resources

```d
import mcp.resources : ResourceContents;

// Static resource
server.addResource(
    "memory://greeting",          // Resource URI
    "Greeting",                   // Name
    "A friendly greeting",        // Description
    () => ResourceContents.makeText(
        "text/plain",
        "Hello, World!"
    )
);

// Dynamic resource
server.addDynamicResource(
    "docs://",                    // Base URI
    "Documentation",              // Name
    "Access documentation files", // Description
    (string path) {
        import std.path : buildPath;
        import std.file : read, exists;
        
        auto fullPath = buildPath("docs", path);
        if (exists(fullPath)) {
            return ResourceContents.makeText(
                "text/markdown",
                cast(string)read(fullPath)
            );
        }
        throw new Exception("File not found: " ~ fullPath);
    }
);

// Template resource
server.addTemplate(
    "weather://{city}/{date}",       // URI template
    "Weather Forecast",              // Name
    "Get weather forecast for a city and date", // Description
    "application/json",              // MIME type
    (string[string] params) {
        // Extract parameters from URI
        auto city = params["city"];
        auto date = params["date"];
        
        // Generate content based on parameters
        return ResourceContents.makeText(
            "application/json",
            `{"city":"` ~ city ~ `","date":"` ~ date ~ `","temp":72}`
        );
    }
);
```

### Prompts

```d
import mcp.prompts;

// Simple text prompt
server.addPrompt(
    "greet",                      // Prompt name
    "A friendly greeting prompt", // Description
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

// Multi-modal prompt with image
server.addPrompt(
    "image_badge",
    "Generate a user badge with avatar",
    [
        PromptArgument("username", "Username to display", true),
        PromptArgument("role", "User role (admin/user)", true)
    ],
    (string name, string[string] args) {
        // Example base64 encoded image data
        auto imageData = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
        
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
```

### Change Notifications

```d
// Get notifier callback when adding a resource
auto notifyChanged = server.addResource(
    "memory://greeting",
    "Greeting",
    "A friendly greeting",
    () => ResourceContents.makeText(
        "text/plain",
        "Hello, World!"
    )
);

// Later, when the resource content changes:
notifyChanged();  // This will trigger a notification to clients
```

### Schema Builder

The schema builder provides a fluent interface for defining JSON schemas:

```d
// Object schema with nested properties
auto personSchema = SchemaBuilder.object()
    .addProperty("name",
        SchemaBuilder.string_()
            .setDescription("User name")
            .stringLength(1, 100))
    .addProperty("age",
        SchemaBuilder.integer()
            .setDescription("User age")
            .range(0, 150))
    .addProperty("email",
        SchemaBuilder.string_()
            .setPattern(r"^[^@]+@[^@]+\.[^@]+$"))
    .addProperty("tags",
        SchemaBuilder.array(
            SchemaBuilder.string_()
        ).optional());

// Array schema with length constraints
auto arraySchema = SchemaBuilder.array(
    SchemaBuilder.string_()
)
.length(1, 10)  // Min and max items
.unique();      // Require unique items

// Enum schema for string values
auto colorSchema = SchemaBuilder.enum_(
    "red", "green", "blue"
);

// Numeric schema with range and multiple-of constraints
auto numberSchema = SchemaBuilder.number()
    .range(0, 100)
    .setMultipleOf(0.5);
```

## Protocol Support

The library implements the MCP specification v2024-11-05:

- JSON-RPC 2.0 message format
- Initialize/initialized lifecycle
- Tool registration and execution with schema validation
- Resource access with static, dynamic, and template resources
- Prompt system with text, image, and resource content
- Change notifications for resources and prompts

## Custom Transports

The library uses stdio transport by default, but you can implement custom transports:

```d
import mcp.transport.base : Transport;

class MyCustomTransport : Transport {
    // Implement the Transport interface methods
    void setMessageHandler(void delegate(JSONValue) handler) { ... }
    void handleMessage(JSONValue message) { ... }
    void sendMessage(JSONValue message) { ... }
    void run() { ... }
    void close() { ... }
}

// Use custom transport
auto transport = new MyCustomTransport();
auto server = new MCPServer(transport, "My Server", "1.0.0");
```

## HTTP Transport

The example application can expose the server over HTTP using Server-Sent Events for notifications. Run the server:

```
dub run :example -- --transport=http --host=127.0.0.1 --port=8080
```

Send a request:

```
curl -X POST http://localhost:8080/mcp \
     -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","id":1,"method":"ping"}'
```

Listen for notifications and responses:

```
curl http://localhost:8080/events
```

## Building

```bash
# Build library
dub build

# Run example
dub run

# Run tests
dub test
```

## License

MIT License

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests to ensure everything works
5. Submit a pull request
