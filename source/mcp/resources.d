/**
 * Resource management for MCP.
 *
 * This module provides functionality for managing resources in the MCP server.
 * Resources are content that can be accessed by URI and can be static, dynamic,
 * or template-based.
 *
 * The module includes:
 * - Resource registry for managing available resources
 * - Static and dynamic resource handling
 * - URI template support
 * - Resource content management
 * - Change notification system
 *
 * Example:
 * ```d
 * // Create a resource registry with notification callback
 * auto registry = new ResourceRegistry((string uri) {
 *     writeln("Resource changed: ", uri);
 * });
 *
 * // Add a static resource
 * registry.addResource(
 *     "resource://example/greeting",
 *     "Greeting",
 *     "A simple greeting resource",
 *     () => ResourceContents.makeText("text/plain", "Hello, world!")
 * );
 *
 * // Add a dynamic resource
 * registry.addDynamicResource(
 *     "resource://example/users/",
 *     "User Profiles",
 *     "Access user profiles by ID",
 *     (string path) => ResourceContents.makeText(
 *         "application/json",
 *         `{"id":"` ~ path ~ `","name":"User ` ~ path ~ `"}`
 *     )
 * );
 * ```
 */
module mcp.resources;

import std.json;
import std.algorithm : sort, startsWith, map;
import std.array : array;
import std.base64;
import std.regex;

import mcp.mime;
import mcp.protocol : MCPError, ErrorCode;

/**
 * Exception thrown when a resource is not found.
 *
 * This exception is used when a client requests a resource that doesn't exist.
 */
class ResourceNotFoundException : MCPError {
    this(string uri, string file = __FILE__, size_t line = __LINE__) {
        super(ErrorCode.methodNotFound, 
              "Resource not found: " ~ uri,
              null, file, line);
    }
}

/**
 * Resource template definition.
 *
 * Templates allow parameterized URIs with variable substitution.
 * For example, a template with URI "resource://users/{id}" can match
 * "resource://users/123" and extract the id parameter.
 */
struct ResourceTemplate {
    string uriTemplate;   // RFC 6570 URI template
    string name;         // Human-readable name
    string description;  // Optional description
    string mimeType;     // Optional MIME type
    private ResourceContents delegate(string[string]) reader;  // Template handler
}

/**
 * Resource content wrapper.
 *
 * This structure encapsulates the content of a resource, which can be
 * either text or binary data, along with its MIME type and URI.
 */
struct ResourceContents {
    string mimeType;     // Content MIME type
    string textContent;  // Text content (if text)
    ubyte[] blob;       // Binary content (if binary)
    private string _uri; // Resource URI (set by registry)
    
    /**
     * Creates a text resource.
     *
     * Params:
     *   mimeType = The MIME type of the content (e.g., "text/plain")
     *   content = The text content
     *
     * Returns:
     *   A ResourceContents object with the specified text content
     */
    static ResourceContents makeText(string mimeType, string content) {
        return ResourceContents(mimeType, content, null);
    }
    
    /**
     * Creates a binary resource.
     *
     * Params:
     *   mimeType = The MIME type of the content (e.g., "image/png")
     *   content = The binary content as a byte array
     *
     * Returns:
     *   A ResourceContents object with the specified binary content
     */
    static ResourceContents makeBinary(string mimeType, ubyte[] content) {
        return ResourceContents(mimeType, null, content);
    }
    
    /**
     * Sets the URI for this resource.
     *
     * This method is used internally by the registry to set the URI
     * when a resource is read.
     *
     * Params:
     *   uri = The URI to set
     */
    void setURI(string uri) { _uri = uri; }
    
    /**
     * Converts the resource contents to JSON format.
     *
     * This method generates the resource content in the format specified
     * by the MCP protocol.
     *
     * Returns:
     *   A JSONValue containing the resource's URI, MIME type, and content
     */
    JSONValue toJSON() const {
        auto json = JSONValue([
            "uri": _uri,
            "mimeType": mimeType
        ]);
        
        if (blob !is null) {
            json["blob"] = Base64.encode(blob);
        } else {
            json["text"] = textContent;
        }
        
        return json;
    }
}

/**
 * Callback function type for resource change notifications.
 *
 * This delegate is called when a resource is updated to notify
 * subscribers of the change.
 */
alias ResourceNotifier = void delegate();

/**
 * Function types for resource content readers.
 *
 * StaticResourceReader is used for resources with fixed content.
 * DynamicResourceReader is used for resources whose content depends on the path.
 */
alias StaticResourceReader = ResourceContents delegate();
alias DynamicResourceReader = ResourceContents delegate(string path);

/**
 * Registry for managing available resources.
 *
 * The ResourceRegistry class provides methods for registering, retrieving,
 * and listing resources available in the MCP server. It supports static
 * resources, dynamic resources, and resource templates.
 */
class ResourceRegistry {
    private {
        struct ResourceEntry {
            string uri;          // Full URI or base URI
            string name;
            string description;
            bool isDynamic;      // true if base URI
            size_t priority;     // URI length for sorting
            StaticResourceReader staticReader;
            DynamicResourceReader dynamicReader;
            ResourceNotifier notifyChanged;
        }
        
        ResourceEntry[] resources;
        ResourceTemplate[] templates;
        void delegate(string) notifySubscribers;
    }
    
    this(void delegate(string) notifyCallback) {
        this.notifySubscribers = notifyCallback;
    }
    
    /**
     * Adds a static resource to the registry.
     *
     * Static resources have fixed content that doesn't change based on the path.
     *
     * Params:
     *   uri = The URI that identifies this resource
     *   name = Human-readable name for the resource
     *   description = Human-readable description
     *   reader = Function that provides the resource content
     *
     * Returns:
     *   A notifier function that can be called to signal resource changes
     */
    ResourceNotifier addResource(string uri, string name, string description,
                               StaticResourceReader reader) {
        resources ~= ResourceEntry(
            uri,
            name,
            description,
            false,     // not dynamic
            0,        // no priority needed
            reader,
            null,     // no dynamic reader
            null      // notifier set below
        );
        
        // Create notifier function
        auto notifier = () {
            if (notifySubscribers)
                notifySubscribers(uri);
        };
        
        // Store notifier
        resources[$-1].notifyChanged = notifier;
        
        return notifier;
    }
    
    /**
     * Adds a dynamic resource to the registry.
     *
     * Dynamic resources have content that varies based on the path after the base URI.
     * For example, a dynamic resource with base URI "resource://users/" can handle
     * requests for "resource://users/123", "resource://users/456", etc.
     *
     * Params:
     *   baseUri = The base URI prefix for this resource
     *   name = Human-readable name for the resource
     *   description = Human-readable description
     *   reader = Function that provides the resource content based on the path
     *
     * Returns:
     *   A notifier function that can be called to signal resource changes
     */
    ResourceNotifier addDynamicResource(string baseUri, string name, 
                                      string description,
                                      DynamicResourceReader reader) {
        resources ~= ResourceEntry(
            baseUri,
            name,
            description,
            true,            // is dynamic
            baseUri.length,  // priority is URI length
            null,           // no static reader
            reader,
            null            // notifier set below
        );
        
        // Sort by priority (longest URI first)
        sort!((a, b) => 
            a.isDynamic && b.isDynamic ? 
                a.priority > b.priority : 
                a.isDynamic < b.isDynamic
        )(resources);
        
        // Create notifier function
        auto notifier = () {
            if (notifySubscribers)
                notifySubscribers(baseUri);
        };
        
        // Store notifier
        resources[$-1].notifyChanged = notifier;
        
        return notifier;
    }
    
    /**
     * Adds a resource template to the registry.
     *
     * Resource templates allow parameterized URIs with variable substitution.
     * For example, a template with URI "resource://users/{id}" can match
     * "resource://users/123" and extract the id parameter.
     *
     * Params:
     *   uriTemplate = The URI template with parameters in {braces}
     *   name = Human-readable name for the template
     *   description = Human-readable description
     *   mimeType = The MIME type of the resource
     *   reader = Function that provides content based on extracted parameters
     *
     * Returns:
     *   A notifier function that can be called to signal template changes
     */
    ResourceNotifier addTemplate(
        string uriTemplate,
        string name,
        string description,
        string mimeType,
        ResourceContents delegate(string[string]) reader
    ) {
        templates ~= ResourceTemplate(
            uriTemplate,
            name,
            description,
            mimeType,
            reader
        );

        // Create notifier function
        auto notifier = () {
            if (notifySubscribers)
                notifySubscribers(uriTemplate);
        };

        return notifier;
    }

    /**
     * Lists all available resource templates.
     *
     * Returns:
     *   A JSONValue containing an array of template definitions
     *   in the format specified by the MCP protocol
     */
    JSONValue listTemplates() {
        import std.algorithm : map;
        import std.array : array;

        return JSONValue([
            "resourceTemplates": templates
                .map!(t => JSONValue([
                    "uriTemplate": t.uriTemplate,
                    "name": t.name,
                    "description": t.description,
                    "mimeType": t.mimeType
                ]))
                .array
        ]);
    }

    /**
     * Extracts parameters from a URI using pattern matching.
     *
     * This method matches a URI against a template pattern and extracts
     * the parameter values.
     *
     * Params:
     *   uriPattern = The URI template pattern with parameters in {braces}
     *   uri = The actual URI to match against the pattern
     *
     * Returns:
     *   A string[string] map of parameter names to values, or null if no match
     */
    private string[string] matchTemplate(string uriPattern, string uri) {
        string[string] params;
        
        // Extract parameter names first
        auto paramMatches = uriPattern.matchAll(regex(r"\{([^}]+)\}"));
        string[] paramNames = [];
        foreach (m; paramMatches) {
            paramNames ~= m[1];
        }
        
        if (paramNames.length == 0) {
            return null;
        }
        
        // Convert URI pattern to regex pattern
        string regexPattern = uriPattern;
        foreach (name; paramNames) {
            regexPattern = regexPattern.replaceAll(
                regex(r"\{" ~ name ~ r"\}"), 
                "([^/]+)"
            );
        }
        auto pattern = regex("^" ~ regexPattern ~ "$");
        
        // Match URI against pattern
        auto matches = matchFirst(uri, pattern);
        if (!matches || matches.length != paramNames.length + 1) { // +1 for full match
            return null;
        }
        
        // Map captured values to parameter names
        for (size_t i = 0; i < paramNames.length; i++) {
            params[paramNames[i]] = matches[i + 1];
        }
        
        return params;
    }

    /**
     * Lists all available resources.
     *
     * Returns:
     *   A JSONValue containing an array of resource definitions
     *   in the format specified by the MCP protocol
     */
    JSONValue listResources() {
        import std.algorithm : map;
        import std.array : array;
        
        return JSONValue([
            "resources": resources
                .map!(r => JSONValue([
                    "uri": r.isDynamic ? r.uri ~ "*" : r.uri,
                    "name": r.name,
                    "description": r.description
                ]))
                .array
        ]);
    }

    /**
     * Reads a resource by URI.
     *
     * This method handles static resources, dynamic resources, and templates.
     * It first tries to match the URI to a static resource, then to a dynamic
     * resource, and finally to a template.
     *
     * Params:
     *   uri = The URI of the resource to read
     *
     * Returns:
     *   The resource contents
     *
     * Throws:
     *   ResourceNotFoundException if the resource is not found
     */
    ResourceContents readResource(string uri) {
        // Try exact matches first
        foreach (ref entry; resources) {
            if (entry.isDynamic) {
                if (uri.startsWith(entry.uri)) {
                    auto path = uri[entry.uri.length .. $];
                    auto contents = entry.dynamicReader(path);
                    contents.setURI(uri);
                    return contents;
                }
            } else {
                if (uri == entry.uri) {
                    auto contents = entry.staticReader();
                    contents.setURI(uri);
                    return contents;
                }
            }
        }
        
        // Try template matches
        foreach (ref tmpl; templates) {
            if (auto params = matchTemplate(tmpl.uriTemplate, uri)) {
                auto contents = tmpl.reader(params);
                contents.setURI(uri);
                return contents;
            }
        }
        
        throw new ResourceNotFoundException(uri);
    }
}
