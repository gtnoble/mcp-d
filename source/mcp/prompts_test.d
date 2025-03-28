module mcp.prompts_test;

import std.json;
import std.exception : assertThrown;

import mcp.prompts;
import mcp.protocol : MCPError;

unittest {
    // Test PromptArgument toJSON
    auto arg = PromptArgument(
        "test_arg",
        "Test argument",
        true
    );
    auto json = arg.toJSON();
    assert(json["name"] == JSONValue("test_arg"));
    assert(json["description"] == JSONValue("Test argument"));
    assert(json["required"] == JSONValue(true));

    // Test optional fields omitted
    auto optionalArg = PromptArgument("opt_arg");
    json = optionalArg.toJSON();
    assert(json["name"] == JSONValue("opt_arg"));
    assert("description" !in json);
    assert("required" !in json);
}

unittest {
    // Test Prompt toJSON
    auto prompt = Prompt(
        "test_prompt",
        "Test prompt",
        [
            PromptArgument("arg1", "First arg", true),
            PromptArgument("arg2", "Second arg", false)
        ]
    );
    auto json = prompt.toJSON();
    assert(json["name"] == JSONValue("test_prompt"));
    assert(json["description"] == JSONValue("Test prompt"));
    assert(json["arguments"].array.length == 2);

    // Test optional fields omitted
    auto minimalPrompt = Prompt("min_prompt");
    json = minimalPrompt.toJSON();
    assert(json["name"] == JSONValue("min_prompt"));
    assert("description" !in json);
    assert("arguments" !in json);
}

unittest {
    // Test content types toJSON
    auto text = TextContent("text", "Hello world");
    auto textJson = text.toJSON();
    assert(textJson["type"] == JSONValue("text"));
    assert(textJson["text"] == JSONValue("Hello world"));

    auto image = ImageContent("image", "base64data", "image/png");
    auto imageJson = image.toJSON();
    assert(imageJson["type"] == JSONValue("image"));
    assert(imageJson["data"] == JSONValue("base64data"));
    assert(imageJson["mimeType"] == JSONValue("image/png"));

    auto message = PromptMessage("user", textJson);
    auto messageJson = message.toJSON();
    assert(messageJson["role"] == JSONValue("user"));
    assert(messageJson["content"] == textJson);
}

// Test PromptRegistry
unittest {
    // Set up test prompt
    auto prompt = Prompt(
        "test",
        "Test prompt",
        [PromptArgument("name", "User name", true)]
    );

    // Test handler that validates arguments and returns messages
    auto handler = delegate(string name, JSONValue args) {
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
    };

    // Create registry
    bool notified = false;
    auto registry = new PromptRegistry((string name) {
        notified = true;
    });

    // Test adding prompt
    registry.addPrompt(prompt, handler);

    // Test duplicate registration
    assertThrown!MCPError(registry.addPrompt(prompt, handler));

    // Test listing prompts
    auto listing = registry.listPrompts();
    assert("prompts" in listing);
    assert(listing["prompts"].array.length == 1);
    assert(listing["prompts"][0]["name"] == JSONValue("test"));

    // Test getting prompt content
    auto args = JSONValue([
        "arguments": JSONValue([
            "name": JSONValue("Alice")
        ])
    ]);
    auto content = registry.getPromptContent("test", args);
    assert("description" in content);
    assert("messages" in content);
    assert(content["messages"][0]["role"] == JSONValue("user"));
    assert(content["messages"][0]["content"]["text"] == JSONValue("Hello Alice"));

    // Test missing required argument
    assertThrown!MCPError(
        registry.getPromptContent("test", JSONValue(null))
    );

    // Test unknown prompt
    assertThrown!MCPError(
        registry.getPromptContent("unknown", args)
    );

    // Test invalid handler response (missing messages)
    auto badHandler = delegate(string name, JSONValue args) {
        return JSONValue([
            "description": "Bad response"
        ]);
    };
    auto badPrompt = Prompt("bad", "Bad prompt");
    registry.addPrompt(badPrompt, badHandler);
    assertThrown!MCPError(
        registry.getPromptContent("bad", JSONValue(null))
    );

    // Test invalid handler response (invalid role)
    auto badRoleHandler = delegate(string name, JSONValue args) {
        return JSONValue([
            "messages": JSONValue([
                JSONValue([
                    "role": JSONValue("invalid"),
                    "content": JSONValue([
                        "type": JSONValue("text"),
                        "text": JSONValue("Hello")
                    ])
                ])
            ])
        ]);
    };
    auto badRolePrompt = Prompt("bad_role", "Bad role prompt");
    registry.addPrompt(badRolePrompt, badRoleHandler);
    assertThrown!MCPError(
        registry.getPromptContent("bad_role", JSONValue(null))
    );
}
