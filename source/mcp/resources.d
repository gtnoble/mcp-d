module mcp.resources;

import std.json;
import std.algorithm : sort, startsWith;
import std.base64;

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
    
    /// Read resource by URI
    ResourceContents readResource(string uri) {
        foreach (ref entry; resources) {
            if (entry.isDynamic) {
                if (uri.startsWith(entry.uri)) {
                    // Extract path after base URI
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
        
        throw new ResourceNotFoundException(uri);
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
}
