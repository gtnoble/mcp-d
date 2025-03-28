module mcp.server_test;

import mcp.server;
import mcp.transport.stdio : Transport;
import mcp.protocol : ErrorCode;
import mcp.resources;
import mcp.prompts;
import mcp.schema;
import std.json;
import std.conv : to;

// Mock transport for testing
class MockTransport : Transport {
    private void delegate(JSONValue) messageHandler;
    JSONValue[] sentMessages;
    private bool closed;

    this() {
        // No initialization needed since messageHandler is set via setMessageHandler
    }

    void setMessageHandler(void delegate(JSONValue) handler) {
        this.messageHandler = handler;
    }

    override void handleMessage(JSONValue message) {
        if (messageHandler !is null) {
            messageHandler(message);
        }
    }

    override void sendMessage(JSONValue message) {
        if (!closed) {
            sentMessages ~= message;
        }
    }

    override void run() {}

    override void close() {
        closed = true;
    }

    void simulateMessage(JSONValue message) {
        if (!closed && messageHandler !is null) {
            messageHandler(message);
        }
    }
}

@("Server - initialization")
unittest {
    auto transport = new MockTransport();
    auto server = new MCPServer(transport, "Test Server", "1.0.0");

    // Test initialization
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(1),
        "method": JSONValue("initialize"),
        "params": JSONValue([
            "protocolVersion": JSONValue("2024-11-05"),
            "capabilities": JSONValue.emptyObject,
            "clientInfo": JSONValue([
                "name": JSONValue("Test Client"),
                "version": JSONValue("1.0.0")
            ])
        ])
    ]));

    assert(transport.sentMessages.length == 1);
    auto response = transport.sentMessages[0];
    assert(response["jsonrpc"] == JSONValue("2.0"));
    assert(response["id"].type == JSONType.integer);
    assert(response["id"].integer == 1);
    assert(response["result"]["serverInfo"]["name"] == JSONValue("Test Server"));
    assert(response["result"]["serverInfo"]["version"] == JSONValue("1.0.0"));
    assert(response["result"]["protocolVersion"] == JSONValue("2024-11-05"));
}

@("Server - tool handling")
unittest {
    auto transport = new MockTransport();
    auto server = new MCPServer(transport, "Test Server", "1.0.0");

    // Initialize server
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(1),
        "method": JSONValue("initialize"),
        "params": JSONValue([
            "protocolVersion": JSONValue("2024-11-05"),
            "capabilities": JSONValue.emptyObject,
            "clientInfo": JSONValue([
                "name": JSONValue("Test Client"),
                "version": JSONValue("1.0.0")
            ])
        ])
    ]));
    transport.sentMessages = [];

    // Add a test tool
    auto schema = SchemaBuilder.object()
        .addProperty("message", SchemaBuilder.string_())
        .addProperty("count", SchemaBuilder.integer().optional());

    server.addTool(
        "echo",
        "Echo Tool - Echoes back the input message",
        schema,
        (args) {
            auto count = "count" in args ? args["count"].integer : 1;
            auto result = args["message"].str;
            for (int i = 1; i < count; i++) {
                result ~= " " ~ args["message"].str;
            }
            return JSONValue(["response": result]);
        }
    );

    // Test tool listing
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(2),
        "method": JSONValue("tools/list")
    ]));

    assert(transport.sentMessages.length == 1);
    auto tools = transport.sentMessages[0]["result"]["tools"].array;
    assert(tools.length == 1);
    assert(tools[0]["name"] == JSONValue("echo"));
    assert(tools[0]["description"] == JSONValue("Echo Tool - Echoes back the input message"));
    transport.sentMessages = [];

    // Test tool execution
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(3),
        "method": JSONValue("tools/call"),
        "params": JSONValue([
            "name": JSONValue("echo"),
            "arguments": JSONValue([
                "message": JSONValue("hello"),
                "count": JSONValue(3)
            ])
        ])
    ]));

    assert(transport.sentMessages.length == 1);
    auto response = transport.sentMessages[0];
    
    assert(response["id"].type == JSONType.integer);
    assert(response["id"].integer == 3);
    assert("result" in response, "Response missing result field");
    assert("content" in response["result"], "Result missing content field");
    auto content = response["result"]["content"].array;
    assert(content.length == 1, "Expected 1 content item");
    assert(content[0]["type"].str == "text", "Expected content type to be text");
    
    // Parse the text content which contains our response JSON
    auto responseJson = parseJSON(content[0]["text"].str);
    assert(responseJson["response"].str == "hello hello hello",
           "Incorrect response content: " ~ responseJson.toString());

    // Test invalid tool name
    transport.sentMessages = [];
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(4),
        "method": JSONValue("tools/call"),
        "params": JSONValue([
            "name": JSONValue("nonexistent"),
            "arguments": JSONValue.emptyObject
        ])
    ]));

    assert(transport.sentMessages.length == 1);
    assert(transport.sentMessages[0]["error"]["code"].integer == ErrorCode.methodNotFound);
}

@("Server - ping handler")
unittest {
    auto transport = new MockTransport();
    auto server = new MCPServer(transport, "Test Server", "1.0.0");

    // Initialize server
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(1),
        "method": JSONValue("initialize"),
        "params": JSONValue([
            "protocolVersion": JSONValue("2024-11-05"),
            "capabilities": JSONValue.emptyObject,
            "clientInfo": JSONValue([
                "name": JSONValue("Test Client"),
                "version": JSONValue("1.0.0")
            ])
        ])
    ]));
    transport.sentMessages = [];

    // Test ping request
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(2),
        "method": JSONValue("ping")
    ]));

    assert(transport.sentMessages.length == 1);
    auto response = transport.sentMessages[0];
    assert(response["jsonrpc"] == JSONValue("2.0"));
    assert(response["id"].integer == 2);
    assert(response["result"].type == JSONType.object);
    assert(response["result"].object.length == 0);
}

@("Server - error handling")
unittest {
    auto transport = new MockTransport();
    auto server = new MCPServer(transport, "Test Server", "1.0.0");

    // Test invalid JSON-RPC version
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("1.0"),
        "id": JSONValue(1),
        "method": JSONValue("initialize"),
        "params": JSONValue.emptyObject
    ]));

    assert(transport.sentMessages.length == 1);
    assert(transport.sentMessages[0]["error"]["code"].integer == ErrorCode.invalidRequest);
    transport.sentMessages = [];

    // Test invalid parameters
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(2),
        "method": JSONValue("initialize"),
        "params": JSONValue("not an object")  // params must be object/array
    ]));

    assert(transport.sentMessages.length == 1);
    auto errorResponse = transport.sentMessages[0];
    assert("error" in errorResponse, "Response missing error field");
    assert(errorResponse["error"]["code"].integer == ErrorCode.invalidRequest);
    transport.sentMessages = [];

    // Make sure server is initialized before testing invalid method
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(0),
        "method": JSONValue("initialize"),
        "params": JSONValue([
            "protocolVersion": JSONValue("2024-11-05"),
            "capabilities": JSONValue.emptyObject,
            "clientInfo": JSONValue([
                "name": JSONValue("Test Client"),
                "version": JSONValue("1.0.0")
            ])
        ])
    ]));
    transport.sentMessages = [];

    // Now test invalid method
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(3),
        "method": JSONValue("invalid_method"),
        "params": JSONValue.emptyObject
    ]));

    assert(transport.sentMessages.length == 1);
    auto methodErrorResponse = transport.sentMessages[0];
    assert("error" in methodErrorResponse, "Response missing error field");
    assert(methodErrorResponse["error"]["code"].integer == ErrorCode.methodNotFound);
}


@("Server - prompt handling")
unittest {
    // Create server with mock transport
    auto transport = new MockTransport();
    auto server = new MCPServer(transport, "Test Server", "1.0.0");

    // Add test prompt
    server.addPrompt(
        "greet",
        "Greeting prompt",
        [PromptArgument("name", "User's name", true)],
        (string name, JSONValue args) {
            auto userName = args["arguments"]["name"].str;
            return JSONValue([
                "description": JSONValue("Test response"),
                "messages": JSONValue([
                    JSONValue([
                        "role": JSONValue("user"),
                        "content": JSONValue([
                            "type": JSONValue("text"),
                            "text": JSONValue("Hello " ~ userName)
                        ])
                    ])
                ])
            ]);
        }
    );

    // Simulate initialization
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(1),
        "method": JSONValue("initialize"),
        "params": JSONValue([
            "protocolVersion": JSONValue("2024-11-05"),
            "capabilities": JSONValue.emptyObject,
            "clientInfo": JSONValue([
                "name": JSONValue("Test Client"),
                "version": JSONValue("1.0.0")
            ])
        ])
    ]));

    // Check capabilities include prompts
    assert(transport.sentMessages.length == 1);
    auto initResponse = transport.sentMessages[0];
    assert(initResponse["result"]["capabilities"]["prompts"]["listChanged"] == JSONValue(true));
    transport.sentMessages = [];

    // Test prompts/list
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(2),
        "method": JSONValue("prompts/list")
    ]));

    assert(transport.sentMessages.length == 1);
    auto prompts = transport.sentMessages[0]["result"]["prompts"].array;
    assert(prompts.length == 1);
    assert(prompts[0]["name"] == JSONValue("greet"));
    assert(prompts[0]["description"] == JSONValue("Greeting prompt"));
    assert(prompts[0]["arguments"].array.length == 1);
    transport.sentMessages = [];

    // Test prompts/get
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(3),
        "method": JSONValue("prompts/get"),
        "params": JSONValue([
            "name": JSONValue("greet"),
            "arguments": JSONValue([
                "name": JSONValue("Alice")
            ])
        ])
    ]));

    assert(transport.sentMessages.length == 1);
    auto getResponse = transport.sentMessages[0];
    assert(getResponse["result"]["description"] == JSONValue("Test response"));
    auto messages = getResponse["result"]["messages"].array;
    assert(messages.length == 1);
    assert(messages[0]["role"] == JSONValue("user"));
    assert(messages[0]["content"]["type"] == JSONValue("text"));
    assert(messages[0]["content"]["text"] == JSONValue("Hello Alice"));
    transport.sentMessages = [];

    // Test prompts/get with missing required argument
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(4),
        "method": JSONValue("prompts/get"),
        "params": JSONValue([
            "name": JSONValue("greet")
        ])
    ]));

    assert(transport.sentMessages.length == 1);
    assert(transport.sentMessages[0]["error"]["code"].integer == ErrorCode.invalidParams);
    transport.sentMessages = [];

    // Test prompts/get with unknown prompt
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(5),
        "method": JSONValue("prompts/get"),
        "params": JSONValue([
            "name": JSONValue("unknown"),
            "arguments": JSONValue.emptyObject
        ])
    ]));

    assert(transport.sentMessages.length == 1);
    assert(transport.sentMessages[0]["error"]["code"].integer == ErrorCode.methodNotFound);
}

@("Server - resource template handling")
unittest {
    // Create server with mock transport
    auto transport = new MockTransport();
    auto server = new MCPServer(transport, "Test Server", "1.0.0");

    // Add template resource
    server.addTemplate(
        "test://{user}/repos/{repo}",
        "Repository",
        "Access user repositories",
        "text/plain",
        (params) { 
            return ResourceContents.makeText(
                "text/plain",
                params["user"] ~ "/" ~ params["repo"]);
        }
    );

    // Simulate initialization
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(1),
        "method": JSONValue("initialize"),
        "params": JSONValue([
            "protocolVersion": JSONValue("2024-11-05"),
            "capabilities": JSONValue.emptyObject,
            "clientInfo": JSONValue([
                "name": JSONValue("Test Client"),
                "version": JSONValue("1.0.0")
            ])
        ])
    ]));

    assert(transport.sentMessages.length == 1);
    assert(transport.sentMessages[0]["result"]["protocolVersion"].str == "2024-11-05");

    // Test template listing
    transport.sentMessages = [];
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(2),
        "method": JSONValue("resources/templates/list")
    ]));

    assert(transport.sentMessages.length == 1);
    auto templates = transport.sentMessages[0]["result"]["resourceTemplates"].array;
    assert(templates.length == 1);
    assert(templates[0]["uriTemplate"].str == "test://{user}/repos/{repo}");
    assert(templates[0]["name"].str == "Repository");
    assert(templates[0]["mimeType"].str == "text/plain");

    // Test resource reading with template
    transport.sentMessages = [];
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(3),
        "method": JSONValue("resources/read"),
        "params": JSONValue(["uri": JSONValue("test://alice/repos/project1")])
    ]));

    assert(transport.sentMessages.length == 1);
    auto response = transport.sentMessages[0];
    assert("jsonrpc" in response);
    assert("result" in response);
    auto contents = response["result"]["contents"].array;
    assert(contents.length == 1);
    assert(contents[0]["text"].str == "alice/project1");
    assert(contents[0]["uri"].str == "test://alice/repos/project1");
    assert(contents[0]["mimeType"].str == "text/plain");

    // Test resource reading with non-matching URI
    transport.sentMessages = [];
    transport.simulateMessage(JSONValue([
        "jsonrpc": JSONValue("2.0"),
        "id": JSONValue(4),
        "method": JSONValue("resources/read"),
        "params": JSONValue(["uri": "test://invalid/path"])
    ]));

    assert(transport.sentMessages.length == 1);
    assert(transport.sentMessages[0]["error"]["code"].integer == ErrorCode.methodNotFound);
}
