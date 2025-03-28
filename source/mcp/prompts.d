module mcp.prompts;

import std.json;
import std.algorithm : map;
import std.array : array;
import mcp.protocol : MCPError, ErrorCode;

/// Prompt argument definition
struct PromptArgument {
    string name;
    string description;  // Optional 
    bool required;      // Optional, defaults to false
    
    JSONValue toJSON() const {
        JSONValue json = [
            "name": JSONValue(name)
        ];
        if (description.length > 0) {
            json["description"] = description;
        }
        if (required) {
            json["required"] = true;
        }
        return json;
    }
}

/// Prompt template definition
struct Prompt {
    string name;
    string description;         // Optional
    PromptArgument[] arguments; // Optional
    
    JSONValue toJSON() const {
        JSONValue json = [
            "name": JSONValue(name)
        ];
        if (description.length > 0) {
            json["description"] = description;
        }
        if (arguments.length > 0) {
            json["arguments"] = arguments.map!(a => a.toJSON()).array;
        }
        return json;
    }
}

/// Message content types
struct TextContent {
    string content;

    JSONValue toJSON() const {
        return JSONValue([
            "type": JSONValue("text"),
            "text": JSONValue(content)
        ]);
    }
}

struct ImageContent {
    string data;      // base64-encoded
    string mimeType;
    
    JSONValue toJSON() const {
        return JSONValue([
            "type": JSONValue("image"),
            "data": JSONValue(data),
            "mimeType": JSONValue(mimeType)
        ]);
    }
}

struct ResourceContent {
    string uri;
    string mimeType;
    string content;  // The actual text content

    JSONValue toJSON() const {
        auto resourceContent = JSONValue([
            "uri": JSONValue(uri),
            "mimeType": JSONValue(mimeType),
            "text": JSONValue(content)  // Always include text field as per spec
        ]);

        return JSONValue([
            "type": JSONValue("resource"),
            "resource": resourceContent
        ]);
    }
}

/// Message definition with union content
struct PromptMessage {
    string role;  // "user" or "assistant"
    union {
        TextContent textContent;
        ImageContent imageContent;
        ResourceContent resourceContent;
    }
    MessageType type;

    enum MessageType {
        text,
        image,
        resource
    }

    JSONValue toJSON() const {
        JSONValue content;
        final switch (type) {
            case MessageType.text:
                content = textContent.toJSON();
                break;
            case MessageType.image:
                content = imageContent.toJSON();
                break;
            case MessageType.resource:
                content = resourceContent.toJSON();
                break;
        }
        return JSONValue([
            "role": JSONValue(role),
            "content": content
        ]);
    }

    // Helper constructors
    static PromptMessage text(string role, string content) {
        PromptMessage msg;
        msg.role = role;
        msg.textContent = TextContent(content);
        msg.type = MessageType.text;
        return msg;
    }

    static PromptMessage image(string role, string data, string mimeType) {
        PromptMessage msg;
        msg.role = role;
        msg.imageContent = ImageContent(data, mimeType);
        msg.type = MessageType.image;
        return msg;
    }

    static PromptMessage resource(string role, string uri, string mimeType, string content = "") {
        PromptMessage msg;
        msg.role = role;
        msg.resourceContent = ResourceContent(uri, mimeType, content);
        msg.type = MessageType.resource;
        return msg;
    }
}

/// Prompt response
struct PromptResponse {
    string description;
    PromptMessage[] messages;

    JSONValue toJSON() const {
        return JSONValue([
            "description": JSONValue(description),
            "messages": JSONValue(messages.map!(m => m.toJSON()).array)
        ]);
    }
}

/// Handler for prompt content generation
alias PromptHandler = PromptResponse delegate(string name, string[string] arguments);

/// Prompt registry
class PromptRegistry {
    private {
        struct StoredPrompt {
            Prompt prompt;
            PromptHandler handler;
        }
        StoredPrompt[string] prompts;
        void delegate(string) notifyCallback;
    }
    
    this(void delegate(string) notifyCallback) {
        this.notifyCallback = notifyCallback;
    }
    
    /// Add prompt
    void addPrompt(Prompt prompt, PromptHandler handler) {
        if (prompt.name.length == 0) {
            throw new MCPError(
                ErrorCode.invalidRequest,
                "Prompt name cannot be empty"
            );
        }
        if (prompt.name in prompts) {
            throw new MCPError(
                ErrorCode.invalidRequest,
                "Prompt already exists: " ~ prompt.name
            );
        }
        prompts[prompt.name] = StoredPrompt(prompt, handler);
    }
    
    /// List available prompts
    JSONValue listPrompts() {
        return JSONValue([
            "prompts": JSONValue(prompts.values
                .map!(p => p.prompt.toJSON())
                .array)
        ]);
    }
    
    /// Get prompt content
    JSONValue getPromptContent(string name, JSONValue rawArguments) {
        auto storedPrompt = name in prompts;
        if (storedPrompt is null) {
            throw new MCPError(
                ErrorCode.methodNotFound,
                "Prompt not found: " ~ name
            );
        }

        // Extract arguments
        string[string] arguments;
        if (rawArguments.type != JSONType.null_ && "arguments" in rawArguments) {
            foreach (string key, value; rawArguments["arguments"].object) {
                if (value.type == JSONType.string) {
                    arguments[key] = value.str;
                }
            }
        }

        // Validate required arguments
        foreach (arg; storedPrompt.prompt.arguments) {
            if (arg.required && (arg.name !in arguments)) {
                throw new MCPError(
                    ErrorCode.invalidParams,
                    "Missing required argument: " ~ arg.name
                );
            }
        }
        
        // Get prompt content
        auto response = storedPrompt.handler(name, arguments);
        
        // Validate response
        if (response.messages.length == 0) {
            throw new MCPError(
                ErrorCode.internalError,
                "Invalid prompt response: missing messages"
            );
        }
        
        // Validate roles
        foreach (message; response.messages) {
            if (message.role != "user" && message.role != "assistant") {
                throw new MCPError(
                    ErrorCode.internalError,
                    "Invalid role: " ~ message.role
                );
            }
        }
        
        return response.toJSON();
    }
}
