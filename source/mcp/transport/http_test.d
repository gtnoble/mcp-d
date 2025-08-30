module mcp.transport.http_test;

import mcp.transport.http : createHttpTransport, HttpTransport;
import std.json;
import std.conv : to;
import core.atomic : atomicLoad, atomicStore;
import std.net.curl;
import core.thread;
import core.time : seconds, msecs;
import std.algorithm : canFind;
import std.socket : TcpSocket, InternetAddress, AddressFamily, SocketOptionLevel, SocketOption;

unittest {
    import std.stdio;
    writefln("launch http server.");
    // Pick a free ephemeral port
    ushort port;
    {
        auto sock = new TcpSocket(AddressFamily.INET);
        scope(exit) sock.close();
        sock.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
        sock.bind(new InternetAddress("127.0.0.1", 0));
        port = cast(ushort)(cast(InternetAddress)sock.localAddress()).port;
    }

    auto transport = createHttpTransport("127.0.0.1", port);
    transport.setMessageHandler((JSONValue msg) { transport.sendMessage(msg); });
    shared bool serverDone = false;
    auto t = new Thread({ transport.run(); atomicStore(serverDone, true); });
    t.isDaemon = true; // don't block process exit if it lingers
    t.start();
    scope(exit) {
        transport.close();
        // Wait up to ~1s for shutdown; skip join if still running
        foreach (_; 0 .. 100) {
            if (atomicLoad(serverDone)) break;
            Thread.sleep(10.msecs);
        }
        // Do not join here to avoid blocking
    }

    string response;
    foreach (_; 0 .. 20) {
        try {
            response = post("http://127.0.0.1:"~port.to!string~"/mcp", "{\"jsonrpc\":\"2.0\",\"id\":1}").idup;
            break;
        } catch (Exception) {
            Thread.sleep(100.msecs);
        }
    }
    assert(response.length > 0, "POST /mcp did not return a response");
    writefln("Okay");
}

unittest {
    import std.stdio;
    writefln("launch http server.");
    // Pick a free ephemeral port
    ushort port;
    {
        auto sock = new TcpSocket(AddressFamily.INET);
        scope(exit) sock.close();
        sock.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
        sock.bind(new InternetAddress("127.0.0.1", 0));
        port = cast(ushort)(cast(InternetAddress)sock.localAddress()).port;
    }

    auto transport = createHttpTransport("127.0.0.1", port);
    transport.setMessageHandler((JSONValue msg) { transport.sendMessage(msg); });
    shared bool serverDone = false;
    auto t = new Thread({ transport.run(); atomicStore(serverDone, true); });
    t.isDaemon = true;
    t.start();
    scope(exit) {
        transport.close();
        foreach (_; 0 .. 100) {
            if (atomicLoad(serverDone)) break;
            Thread.sleep(10.msecs);
        }
        // Do not join here to avoid blocking
    }

    // Wait until server is reachable before opening SSE
    string readyResp;
    foreach (_; 0 .. 50) { // up to ~5s
        try {
            readyResp = post("http://127.0.0.1:"~port.to!string~"/mcp", "{\"jsonrpc\":\"2.0\",\"id\":1}").idup;
            if (readyResp.length) break;
        } catch (Exception) {
            Thread.sleep(100.msecs);
        }
    }
    assert(readyResp.length > 0, "Server did not start within timeout");

    string sseData;
    shared bool sseReady = false;
    auto t2 = new Thread({
        auto http = HTTP("http://127.0.0.1:"~port.to!string~"/events");
        http.method = HTTP.Method.get;
        http.connectTimeout = 2.seconds;
        http.operationTimeout = 20.seconds;
        http.onReceive = (ubyte[] data){
            sseData ~= cast(string)data;
            atomicStore(sseReady, true);
            if (sseData.canFind("ping")) return 0; // abort stream after receiving ping
            return data.length;
        };
        try { http.perform(); } catch (Exception) {}
    });
    t2.start();
    // Wait until SSE delivers any byte (prelude/heartbeat) or timeout
    foreach (_; 0 .. 20) {
        if (atomicLoad(sseReady)) break;
        Thread.sleep(100.msecs);
    }
    transport.sendMessage(JSONValue(["jsonrpc":JSONValue("2.0"),"method":JSONValue("ping")]));
    t2.join();
    assert(sseData.canFind("ping"));
    writefln("Okay");
}
