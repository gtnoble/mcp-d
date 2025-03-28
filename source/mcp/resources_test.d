module mcp.resources_test;

import mcp.resources;
import mcp.mime;
import std.json;
import std.base64;
import std.algorithm : equal, endsWith;

@("ResourceContents - text resource creation")
unittest {
    // Create text resource
    auto content = ResourceContents.makeText("text/plain", "Hello World");
    assert(content.mimeType == "text/plain");
    assert(content.textContent == "Hello World");
    assert(content.blob is null);

    // Test JSON conversion
    auto json = content.toJSON();
    assert(json.type == JSONType.object);
    assert(json["mimeType"].str == "text/plain");
    assert(json["text"].str == "Hello World");

    // Test empty content
    auto emptyContent = ResourceContents.makeText("text/plain", "");
    assert(emptyContent.textContent == "");
    assert(emptyContent.blob is null);

    // Test Unicode content
    auto unicodeContent = ResourceContents.makeText("text/plain", "Hello 世界");
    auto unicodeJson = unicodeContent.toJSON();
    assert(unicodeJson["text"].str == "Hello 世界");
}

@("ResourceContents - binary resource creation")
unittest {
    // Create binary resource
    ubyte[] data = [1, 2, 3, 4, 5];
    auto content = ResourceContents.makeBinary("application/octet-stream", data);
    assert(content.mimeType == "application/octet-stream");
    assert(content.textContent is null);
    assert(content.blob == data);

    // Test JSON conversion
    auto json = content.toJSON();
    assert(json.type == JSONType.object);
    assert(json["mimeType"].str == "application/octet-stream");
    assert(json["blob"].str == Base64.encode(data));

    // Test empty binary content
    auto emptyContent = ResourceContents.makeBinary("application/octet-stream", []);
    assert(emptyContent.textContent is null);
    assert(emptyContent.blob.length == 0);
}

@("ResourceRegistry - static resources")
unittest {
    bool notified = false;
    auto registry = new ResourceRegistry((uri) { notified = true; });

    // Add static resource
    auto notifier = registry.addResource(
        "test://static",
        "Test Resource",
        "A test static resource",
        () => ResourceContents.makeText("text/plain", "Static Content")
    );

    // Read resource
    auto content = registry.readResource("test://static");
    assert(content.mimeType == "text/plain");
    assert(content.textContent == "Static Content");

    auto json = content.toJSON();
    assert(json["uri"].str == "test://static");

    // Test notification
    notifier();
    assert(notified);

    // List resources
    auto list = registry.listResources();
    assert(list["resources"].array.length == 1);
    assert(list["resources"][0]["uri"].str == "test://static");
    assert(list["resources"][0]["name"].str == "Test Resource");
    assert(list["resources"][0]["description"].str == "A test static resource");
}

@("ResourceRegistry - dynamic resources")
unittest {
    auto registry = new ResourceRegistry(null);

    // Add dynamic resource
    registry.addDynamicResource(
        "test://dynamic/",
        "Dynamic Resource",
        "A test dynamic resource",
        (path) => ResourceContents.makeText("text/plain", "Dynamic: " ~ path)
    );

    // Read resource with path
    auto content = registry.readResource("test://dynamic/path/to/resource");
    assert(content.mimeType == "text/plain");
    assert(content.textContent == "Dynamic: path/to/resource");

    auto json = content.toJSON();
    assert(json["uri"].str == "test://dynamic/path/to/resource");

    // List resources
    auto list = registry.listResources();
    assert(list["resources"].array.length == 1);
    assert(list["resources"][0]["uri"].str == "test://dynamic/*");
    assert(list["resources"][0]["name"].str == "Dynamic Resource");
}

@("ResourceRegistry - overlapping URI prefixes")
unittest {
    auto registry = new ResourceRegistry(null);

    // Add resources with overlapping prefixes (longer should match first)
    registry.addDynamicResource(
        "test://dynamic/longer/",
        "Longer Prefix",
        "Resource with longer prefix",
        (path) => ResourceContents.makeText("text/plain", "Longer: " ~ path)
    );

    registry.addDynamicResource(
        "test://dynamic/",
        "Shorter Prefix",
        "Resource with shorter prefix",
        (path) => ResourceContents.makeText("text/plain", "Shorter: " ~ path)
    );

    // Test longer prefix matches first
    auto content1 = registry.readResource("test://dynamic/longer/path");
    assert(content1.textContent == "Longer: path");
    auto json1 = content1.toJSON();
    assert(json1["uri"].str == "test://dynamic/longer/path");

    // Test shorter prefix matches when longer doesn't
    auto content2 = registry.readResource("test://dynamic/other/path");
    assert(content2.textContent == "Shorter: other/path");
    auto json2 = content2.toJSON();
    assert(json2["uri"].str == "test://dynamic/other/path");
}

@("ResourceRegistry - error handling")
unittest {
    auto registry = new ResourceRegistry(null);

    // Test non-existent resource
    import std.exception : assertThrown;
    assertThrown!ResourceNotFoundException(
        registry.readResource("test://nonexistent")
    );

    // Add resource and test invalid path
    registry.addDynamicResource(
        "test://base/",
        "Test Resource",
        "Test resource",
        (path) => ResourceContents.makeText("text/plain", path)
    );

    // Should still work with empty path
    auto content = registry.readResource("test://base/");
    assert(content.textContent == "");
    auto json = content.toJSON();
    assert(json["uri"].str == "test://base/");
}

@("ResourceRegistry - notification system")
unittest {
    string lastNotifiedUri;
    auto registry = new ResourceRegistry((uri) { lastNotifiedUri = uri; });

    // Add multiple resources
    auto notifier1 = registry.addResource(
        "test://resource1",
        "Resource 1",
        "First test resource",
        () => ResourceContents.makeText("text/plain", "Content 1")
    );

    auto notifier2 = registry.addDynamicResource(
        "test://resource2/",
        "Resource 2",
        "Second test resource",
        (path) => ResourceContents.makeText("text/plain", "Content 2")
    );

    // Test notifications for each resource
    notifier1();
    assert(lastNotifiedUri == "test://resource1");

    notifier2();
    assert(lastNotifiedUri == "test://resource2/");
}

@("ResourceRegistry - template resources")
unittest {
    auto registry = new ResourceRegistry(null);

    // Add template resource
    registry.addTemplate(
        "test://{user}/repos/{repo}",
        "Repository",
        "Access user repositories",
        "text/plain",
        (params) {
            import std.stdio;
            writeln("Params: ", params);  // Debug print
            
            // Direct value assertions
            assert(params["user"] == "alice" || params["user"] == "bob", 
                   "Unexpected or missing user parameter: " ~ params["user"]);
            assert(params["repo"] == "project1" || params["repo"] == "demo",
                   "Unexpected or missing repo parameter: " ~ params["repo"]);
                   
            return ResourceContents.makeText(
                "text/plain", 
                params["user"] ~ "/" ~ params["repo"]
            );
        }
    );

    // Test accessing templated resource
    auto content = registry.readResource("test://alice/repos/project1");
    assert(content.textContent == "alice/project1");
    auto json = content.toJSON();
    assert(json["uri"].str == "test://alice/repos/project1");

    // Test accessing with different parameters
    content = registry.readResource("test://bob/repos/demo");
    assert(content.textContent == "bob/demo");
    json = content.toJSON();
    assert(json["uri"].str == "test://bob/repos/demo");

    // Test non-matching URI format
    import std.exception : assertThrown;
    assertThrown!ResourceNotFoundException(
        registry.readResource("test://alice/invalid/project1")
    );

    // Test template listing
    auto list = registry.listTemplates();
    assert(list["resourceTemplates"].array.length == 1);
    auto tmpl = list["resourceTemplates"][0];
    assert(tmpl["uriTemplate"].str == "test://{user}/repos/{repo}");
    assert(tmpl["name"].str == "Repository");
    assert(tmpl["description"].str == "Access user repositories");
    assert(tmpl["mimeType"].str == "text/plain");
}

@("ResourceRegistry - template with optional MIME type")
unittest {
    auto registry = new ResourceRegistry(null);

    // Add template without MIME type
    registry.addTemplate(
        "files://{path}",
        "File Access",
        "Access files by path",
        null,  // No MIME type specified
        (params) {
            assert("path" in params);
            string path = params["path"];
            // Set MIME type based on path
            string mimeType = path.endsWith(".txt") ? "text/plain" : "application/octet-stream";
            return ResourceContents.makeText(mimeType, "Content of " ~ path);
        }
    );

    // Test with different file types
    auto txtContent = registry.readResource("files://test.txt");
    assert(txtContent.mimeType == "text/plain");

    auto binContent = registry.readResource("files://data.bin");
    assert(binContent.mimeType == "application/octet-stream");
}

@("ResourceRegistry - template notification")
unittest {
    string lastNotifiedUri;
    auto registry = new ResourceRegistry((uri) { lastNotifiedUri = uri; });

    // Add template resource with notification
    auto notifier = registry.addTemplate(
        "notify://{id}",
        "Notification Test",
        "Test template notifications",
        "text/plain",
        (params) => ResourceContents.makeText("text/plain", params["id"])
    );

    // Test notification
    notifier();
    assert(lastNotifiedUri == "notify://{id}");
}
