/**
 * Prompt system for MCP.
 *
 * This module provides functionality for managing prompts in the MCP server.
 * Prompts are pre-defined message templates that can be used by AI models
 * to generate consistent responses.
 *
 * The module includes:
 * - Prompt registry for managing available prompts
 * - Message content types (text, image, resource)
 * - Prompt argument handling
 * - Response formatting
 *
 * Example:
 * ```d
 * // Create a prompt registry with notification callback
 * auto registry = new PromptRegistry((string name) {
 *     writeln("Prompt changed: ", name);
 * });
 *
 * // Define a prompt
 * registry.addPrompt(
 *     Prompt("greeting", "A friendly greeting", [
 *         PromptArgument("name", "User's name", true)
 *     ]),
 *     (string name, string[string] args) {
 *         return PromptResponse(
 *             "A greeting for " ~ args["name"],
 *             [PromptMessage.text("assistant", "Hello, " ~ args["name"] ~ "!")]
 *         );
 *     }
 * );
 * ```
 */
module mcp.prompts;

import std.json;
import std.algorithm : map;
import std.array : array;
import mcp.protocol : MCPError, ErrorCode;

/**
 * Prompt argument definition.
 *
 * Prompt arguments define the parameters that can be passed to a prompt
 * when it is requested.
 */
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

/**
 * Prompt template definition.
 *
 * A prompt template defines a named prompt with optional description
 * and arguments that can be used to generate content.
 */
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

/**
 * Message content types.
 *
 * These structures define the different types of content that can be
 * included in prompt messages: text, images, and resources.
 */
/**
 * Text content for messages.
 *
 * This structure represents simple text content in a message.
 */
struct TextContent {
    string content;

    JSONValue toJSON() const {
        return JSONValue([
            "type": JSONValue("text"),
            "text": JSONValue(content)
        ]);
    }
}

/**
 * Image content for messages.
 *
 * This structure represents image content in a message,
 * stored as base64-encoded data with a MIME type.
 */
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

/**
 * Resource content for messages.
 *
 * This structure represents a reference to a resource in a message,
 * identified by a URI and MIME type, with optional inline content.
 */
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

/**
 * Message definition with union content.
 *
 * A PromptMessage represents a single message in a prompt response,
 * with a role (user or assistant) and content of various types.
 */
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

    /**
     * Helper constructors for creating messages of different types.
     *
     * These static methods provide a convenient way to create messages
     * with different content types without directly manipulating the union.
     */
    /**
     * Creates a text message.
     *
     * Params:
     *   role = The message role ("user" or "assistant")
     *   content = The text content
     *
     * Returns:
     *   A PromptMessage with text content
     */
    static PromptMessage text(string role, string content) {
        PromptMessage msg;
        msg.role = role;
        msg.textContent = TextContent(content);
        msg.type = MessageType.text;
        return msg;
    }

    /**
     * Creates an image message.
     *
     * Params:
     *   role = The message role ("user" or "assistant")
     *   data = The base64-encoded image data
     *   mimeType = The image MIME type (e.g., "image/png")
     *
     * Returns:
     *   A PromptMessage with image content
     */
    static PromptMessage image(string role, string data, string mimeType) {
        PromptMessage msg;
        msg.role = role;
        msg.imageContent = ImageContent(data, mimeType);
        msg.type = MessageType.image;
        return msg;
    }

    /**
     * Creates a resource message.
     *
     * Params:
     *   role = The message role ("user" or "assistant")
     *   uri = The resource URI
     *   mimeType = The resource MIME type
     *   content = Optional inline content
     *
     * Returns:
     *   A PromptMessage with resource content
     */
    static PromptMessage resource(string role, string uri, string mimeType, string content = "") {
        PromptMessage msg;
        msg.role = role;
        msg.resourceContent = ResourceContent(uri, mimeType, content);
        msg.type = MessageType.resource;
        return msg;
    }
}

/**
 * Prompt response.
 *
 * A PromptResponse represents the content returned when a prompt is requested,
 * consisting of a description and an array of messages.
 */
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

/**
 * Handler for prompt content generation.
 *
 * This delegate type defines the signature for prompt handler functions,
 * which generate prompt content based on the prompt name and arguments.
 */
alias PromptHandler = PromptResponse delegate(string name, string[string] arguments);

/**
 * Registry for managing available prompts.
 *
 * The PromptRegistry class provides methods for registering, retrieving,
 * and listing prompts available in the MCP server.
 */
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
    
    /**
     * Registers a new prompt with the registry.
     *
     * Params:
     *   prompt = The prompt definition
     *   handler = Function to generate prompt content when requested
     *
     * Throws:
     *   MCPError if a prompt with the same name already exists
     *   MCPError if the prompt name is empty
     */
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
    
    /**
     * Lists all available prompts.
     *
     * Returns:
     *   A JSONValue containing an array of prompt definitions
     *   in the format specified by the MCP protocol
     */
    JSONValue listPrompts() {
        return JSONValue([
            "prompts": JSONValue(prompts.values
                .map!(p => p.prompt.toJSON())
                .array)
        ]);
    }
    
    /**
     * Gets the content for a specific prompt.
     *
     * This method retrieves a prompt by name, validates the arguments,
     * calls the handler function, and formats the response.
     *
     * Params:
     *   name = The name of the prompt to retrieve
     *   rawArguments = The arguments to pass to the prompt handler
     *
     * Returns:
     *   A JSONValue containing the prompt response in the format
     *   specified by the MCP protocol
     *
     * Throws:
     *   MCPError if the prompt does not exist
     *   MCPError if required arguments are missing
     *   MCPError if the response is invalid
     */
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
