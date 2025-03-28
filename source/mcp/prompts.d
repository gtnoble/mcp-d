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
            json["arguments"] = arguments.map!(a => a.toJSON()).array();
        }
        return json;
    }
}

/// Message content types
struct TextContent {
    string type = "text";
    string text;
    
    JSONValue toJSON() const {
        return JSONValue([
            "type": JSONValue(type),
            "text": JSONValue(text)
        ]);
    }
}

struct ImageContent {
    string type = "image";
    string data;     // base64-encoded
    string mimeType;
    
    JSONValue toJSON() const {
        return JSONValue([
            "type": JSONValue(type),
            "data": JSONValue(data),
            "mimeType": JSONValue(mimeType)
        ]);
    }
}

struct PromptMessage {
    string role;      // "user" or "assistant"
    JSONValue content;  // TextContent | ImageContent | EmbeddedResource
    
    JSONValue toJSON() const {
        JSONValue jsonContent = content;
        return JSONValue([
            "role": JSONValue(role),
            "content": jsonContent
        ]);
    }
}

/// Handler for prompt content generation
alias PromptHandler = JSONValue delegate(string name, JSONValue arguments);

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
        import std.algorithm : map;
        import std.array : array;
        
        return JSONValue([
            "prompts": JSONValue(prompts.values
                .map!(p => p.prompt.toJSON())
                .array)
        ]);
    }
    
    /// Get prompt content
    JSONValue getPromptContent(string name, JSONValue arguments) {
        auto storedPrompt = name in prompts;
        if (storedPrompt is null) {
            throw new MCPError(
                ErrorCode.methodNotFound,
                "Prompt not found: " ~ name
            );
        }
        
        // Validate required arguments
        foreach (arg; storedPrompt.prompt.arguments) {
            if (arg.required && (
                arguments.type == JSONType.null_ ||
                "arguments" !in arguments ||
                arg.name !in arguments["arguments"]
            )) {
                throw new MCPError(
                    ErrorCode.invalidParams,
                    "Missing required argument: " ~ arg.name
                );
            }
        }
        
        // Get prompt content from handler
        auto result = storedPrompt.handler(name, arguments);
        
        // Validate message roles
        if ("messages" !in result || result["messages"].type != JSONType.array) {
            throw new MCPError(
                ErrorCode.internalError,
                "Invalid prompt handler response: missing or invalid messages array"
            );
        }
        
        foreach (message; result["messages"].array) {
            if ("role" !in message || message["role"].type != JSONType.string) {
                throw new MCPError(
                    ErrorCode.internalError,
                    "Invalid prompt message: missing or invalid role"
                );
            }
            
            auto role = message["role"].str;
            if (role != "user" && role != "assistant") {
                throw new MCPError(
                    ErrorCode.internalError,
                    "Invalid role: " ~ role
                );
            }
        }
        
        return result;
    }
}
