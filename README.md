# D MCP Server Library

A D language implementation of the Model Context Protocol (MCP) server, focusing on stdio transport.

## Features

- MCP protocol v2024-11-05 support
- stdio transport implementation
- Type-safe schema builder
- Resource system with change notifications
- Simple and clean API

## Installation

Add to your `dub.json`:
```json
{
    "dependencies": {
        "d-mcp-server": "~>0.1.0"
    }
}
```

## Usage

### Basic Server

```d
import mcp.server;
import mcp.schema;

void main() {
    // Create server
    auto server = new MCPServer("My MCP Server", "1.0.0");
    
    // Add a tool
    server.addTool(
        "add",
        "Add two numbers",
        SchemaBuilder.object()
            .addProperty("a", 
                SchemaBuilder.number().setDescription("First number"))
            .addProperty("b", 
                SchemaBuilder.number().setDescription("Second number")),
        (args) {
            auto a = args["a"].get!double;
            auto b = args["b"].get!double;
            return JSONValue(a + b);
        }
    );
    
    // Start server
    server.start();
}
```

### Resources

```d
// Static resource
server.addResource(
    "memory://greeting",
    "Greeting",
    "A friendly greeting",
    () => ResourceContents.text(
        "text/plain",
        "Hello, World!"
    )
);

// Dynamic resource
server.addDynamicResource(
    "docs://",
    "Documentation",
    "Access documentation files",
    (string path) {
        auto fullPath = buildPath("docs", path);
        return ResourceContents.fromFile(fullPath);
    }
);
```

### Change Notifications

```d
// Get notifier callback
auto notifyChanged = server.addResource(...);

// Call when resource changes
notifyChanged();
```

### Schema Builder

```d
// Object schema
auto schema = SchemaBuilder.object()
    .addProperty("name",
        SchemaBuilder.string_()
            .setDescription("User name")
            .stringLength(1, 100))
    .addProperty("age",
        SchemaBuilder.number()
            .setDescription("User age")
            .range(0, 150));

// Array schema
auto arraySchema = SchemaBuilder.array(
    SchemaBuilder.string_()
        .setDescription("Item")
);

// Enum schema
auto enumSchema = SchemaBuilder.enum_(
    "red", "green", "blue"
);
```

## Protocol Support

- JSON-RPC 2.0 message format
- Initialize/initialized lifecycle
- Tool registration and execution
- Resource access
- Change notifications

## License

MIT License

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request
