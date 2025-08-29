/**
 * Base transport interface for MCP communication.
 *
 * This module defines the Transport interface which all transport
 * implementations must implement.
 */
module mcp.transport.base;

import std.json;

interface Transport {
    void setMessageHandler(void delegate(JSONValue) handler);
    void handleMessage(JSONValue message);
    void sendMessage(JSONValue message);
    void run();
    void close();
}
