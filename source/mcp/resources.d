module mcp.resources;

import std.json;
import std.algorithm : sort, startsWith, map;
import std.array : array;
import std.base64;
import std.regex;

import mcp.mime;
import mcp.protocol : MCPError, ErrorCode;

/// Resource not found error
class ResourceNotFoundException : MCPError {
    this(string uri, string file = __FILE__, size_t line = __LINE__) {
        super(ErrorCode.methodNotFound, 
              "Resource not found: " ~ uri,
              null, file, line);
    }
}

/// Resource template definition
struct ResourceTemplate {
    string uriTemplate;   // RFC 6570 URI template
    string name;         // Human-readable name
    string description;  // Optional description
    string mimeType;     // Optional MIME type
    private ResourceContents delegate(string[string]) reader;  // Template handler
}

/// Resource content wrapper
struct ResourceContents {
    string mimeType;     // Content MIME type
    string textContent;  // Text content (if text)
    ubyte[] blob;       // Binary content (if binary)
    private string _uri; // Resource URI (set by registry)
    
    /// Create text resource
    static ResourceContents makeText(string mimeType, string content) {
        return ResourceContents(mimeType, content, null);
    }
    
    /// Create binary resource
    static ResourceContents makeBinary(string mimeType, ubyte[] content) {
        return ResourceContents(mimeType, null, content);
    }
    
    /// Set URI (used by registry)
    void setURI(string uri) { _uri = uri; }
    
    /// Convert to MCP format
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

/// Callback for resource changes
alias ResourceNotifier = void delegate();

/// Reader functions
alias StaticResourceReader = ResourceContents delegate();
alias DynamicResourceReader = ResourceContents delegate(string path);

/// Resource registry
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
    
    /// Add static resource
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
    
    /// Add dynamic resource with base URI
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
    
    /// Add a resource template
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

    /// List available templates
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

    /// Extract parameters from URI using pattern matching
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

    /// List available resources
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

    /// Read resource by URI, including template handling
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
