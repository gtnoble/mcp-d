/**
 * HTTP transport implementation for MCP.
 *
 * This transport exposes two endpoints:
 *  - POST /mcp   : accepts JSON-RPC messages
 *  - GET  /events: Server-Sent Events stream for responses/notifications
 */
module mcp.transport.http;

import std.json;

import vibe.http.server;
import vibe.http.router;
import vibe.core.core : runEventLoop, exitEventLoop, yield, Fiber;
import vibe.core.stream : OutputStream;
import std.algorithm : countUntil;

import mcp.transport.base;

class HttpTransport : Transport {
    private {
        void delegate(JSONValue) messageHandler;
        HTTPServerListener listener;
        OutputStream[] clients;
        JSONValue*[Fiber] responseSlots;
        string host;
        ushort port;
        bool running;
    }

    this(string host = "127.0.0.1", ushort port = 8080) {
        this.host = host;
        this.port = port;
    }

    void setMessageHandler(void delegate(JSONValue) handler) {
        messageHandler = handler;
    }

    void handleMessage(JSONValue message) {
        if (messageHandler !is null) messageHandler(message);
    }

    void sendMessage(JSONValue message) {
        auto fb = Fiber.getThis();
        synchronized(this) {
            if (fb in responseSlots) {
                *responseSlots[fb] = message;
                responseSlots.remove(fb);
            }
            size_t i = 0;
            while (i < clients.length) {
                auto c = clients[i];
                scope(exit) {}
                try {
                    c.write("data: " ~ message.toString() ~ "\n\n");
                    c.flush();
                    ++i;
                } catch (Exception) {
                    clients = clients[0 .. i] ~ clients[i + 1 .. $];
                }
            }
        }
    }

    private void handlePost(scope HTTPServerRequest req, scope HTTPServerResponse res) {
        import std.conv : to;
        auto body = cast(string)req.bodyReader.readAll().idup;
        JSONValue msg;
        try {
            msg = parseJSON(body);
        } catch (JSONException e) {
            auto err = JSONValue([
                "jsonrpc": JSONValue("2.0"),
                "error": JSONValue([
                    "code": JSONValue(-32700),
                    "message": JSONValue("Parse error")
                ])
            ]);
            res.headers["Content-Type"] = "application/json";
            res.writeBody(err.toString());
            return;
        }

        JSONValue response;
        auto fb = Fiber.getThis();
        synchronized(this) responseSlots[fb] = &response;
        handleMessage(msg);
        synchronized(this) responseSlots.remove(fb);

        res.headers["Content-Type"] = "application/json";
        auto idField = msg["id"];
        if (idField.type == JSON_TYPE.NULL){
            res.statusCode = 204;
            res.writeBody("");
        } else {
            res.writeBody(response.toString());
        }
    }

    private void handleEvents(scope HTTPServerRequest req, scope HTTPServerResponse res) {
        res.headers["Content-Type"] = "text/event-stream";
        res.headers["Cache-Control"] = "no-cache";
        res.headers["Connection"] = "keep-alive";
        auto stream = res.bodyWriter;
        synchronized(this) clients ~= stream;
        scope(exit) synchronized(this) {
            auto idx = clients.countUntil(stream);
            if (idx != -1) clients = clients[0 .. idx] ~ clients[idx + 1 .. $];
        }
        while (running && stream.isOpen) {
            yield();
        }
    }

    void run() {
        auto router = new URLRouter;
        router.post("/mcp", &handlePost);
        router.get("/events", &handleEvents);
        auto settings = new HTTPServerSettings;
        settings.host = host;
        settings.port = port;
        listener = listenHTTP(settings, router);
        running = true;
        runEventLoop();
    }

    void close() {
        running = false;
        if (listener !is null) listener.stopListening();
        synchronized(this) foreach (c; clients) { c.close(); }
        exitEventLoop();
    }
}

HttpTransport createHttpTransport(string host = "127.0.0.1", ushort port = 8080) {
    return new HttpTransport(host, port);
}
