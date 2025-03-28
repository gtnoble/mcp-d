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
    auto text = TextContent("Hello world");
    auto textJson = text.toJSON();
    assert(textJson["type"] == JSONValue("text"));
    assert(textJson["text"] == JSONValue("Hello world"));

    auto image = ImageContent("base64data", "image/png");
    auto imageJson = image.toJSON();
    assert(imageJson["type"] == JSONValue("image"));
    assert(imageJson["data"] == JSONValue("base64data"));
    assert(imageJson["mimeType"] == JSONValue("image/png"));

    auto resource = ResourceContent("resource://test", "text/plain", "content");
    auto resourceJson = resource.toJSON();
    assert(resourceJson["type"] == JSONValue("resource"));
    assert(resourceJson["resource"]["uri"] == JSONValue("resource://test"));
    assert(resourceJson["resource"]["mimeType"] == JSONValue("text/plain"));
    assert(resourceJson["resource"]["text"] == JSONValue("content"));
}

unittest {
    // Test PromptMessage helper constructors
    auto textMsg = PromptMessage.text("user", "Hello world");
    assert(textMsg.role == "user");
    assert(textMsg.type == PromptMessage.MessageType.text);
    assert(textMsg.textContent.content == "Hello world");

    auto imageMsg = PromptMessage.image("assistant", "base64data", "image/png");
    assert(imageMsg.role == "assistant");
    assert(imageMsg.type == PromptMessage.MessageType.image);
    assert(imageMsg.imageContent.data == "base64data");
    assert(imageMsg.imageContent.mimeType == "image/png");

    auto resourceMsg = PromptMessage.resource(
        "assistant", "resource://test", "text/plain", "content"
    );
    assert(resourceMsg.role == "assistant");
    assert(resourceMsg.type == PromptMessage.MessageType.resource);
    assert(resourceMsg.resourceContent.uri == "resource://test");
    assert(resourceMsg.resourceContent.mimeType == "text/plain");
    assert(resourceMsg.resourceContent.content == "content");
}

// Test PromptRegistry
unittest {
    // Set up test prompt
    auto prompt = Prompt(
        "test1",
        "Test prompt",
        [PromptArgument("name", "User name", true)]
    );

    // Test handler that validates arguments and returns messages
    auto handler = delegate(string name, string[string] args) {
        return PromptResponse(
            "Test response",
            [PromptMessage.text("user", "Hello " ~ args["name"])]
        );
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
    assert(listing["prompts"][0]["name"] == JSONValue("test1"));

    // Test getting prompt content
    auto args = JSONValue([
        "arguments": JSONValue([
            "name": JSONValue("Alice")
        ])
    ]);
    auto content = registry.getPromptContent("test1", args);
    assert("description" in content);
    assert("messages" in content);
    assert(content["messages"][0]["role"] == JSONValue("user"));
    auto messages = content["messages"].array;
    assert(messages[0]["content"]["text"] == JSONValue("Hello Alice"));
}

unittest {
    // Test error cases
    auto registry = new PromptRegistry(null);
    auto prompt = Prompt("test2");
    
    // Test empty prompt name
    auto badPrompt = Prompt("", "Bad prompt");
    assertThrown!MCPError(
        registry.addPrompt(badPrompt, (n, a) => PromptResponse())
    );

    // Test missing required arguments
    registry.addPrompt(
        Prompt("test5", "Test", [PromptArgument("arg", "", true)]),
        (n, a) => PromptResponse()
    );
    assertThrown!MCPError(
        registry.getPromptContent("test5", JSONValue(null))
    );

    // Test unknown prompt
    assertThrown!MCPError(
        registry.getPromptContent("unknown", JSONValue.emptyObject)
    );

    // Test empty response
    registry.addPrompt(
        Prompt("test3"),
        (n, a) => PromptResponse()  // Empty response
    );
    assertThrown!MCPError(
        registry.getPromptContent("test3", JSONValue.emptyObject)
    );

    // Test invalid role
    registry.addPrompt(
        Prompt("test4"),
        (n, a) => PromptResponse("", [
            PromptMessage.text("invalid", "Hello")
        ])
    );
    assertThrown!MCPError(
        registry.getPromptContent("test4", JSONValue.emptyObject)
    );
}
