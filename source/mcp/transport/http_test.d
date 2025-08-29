module mcp.transport.http_test;

import mcp.transport.http : createHttpTransport, HttpTransport;
import std.json;
import std.net.curl;
import core.thread;
import core.time : seconds;
import std.algorithm : canFind;

unittest {
    auto transport = createHttpTransport("127.0.0.1", 8091);
    transport.setMessageHandler((JSONValue msg) { transport.sendMessage(msg); });
    auto t = new Thread({ transport.run(); });
    t.start();
    scope(exit) { transport.close(); t.join(); }

    auto response = post("http://127.0.0.1:8091/mcp", "{\"jsonrpc\":\"2.0\",\"id\":1}");
    assert(response.length > 0);

    string sseData;
    auto t2 = new Thread({
        auto http = HTTP();
        http.method = HTTP.Method.get;
        http.run("http://127.0.0.1:8091/events", (ubyte[] data){ sseData ~= cast(string)data; return data.length; });
    });
    t2.start();
    Thread.sleep(1.seconds);
    transport.sendMessage(JSONValue(["jsonrpc":JSONValue("2.0"),"method":JSONValue("ping")]));
    Thread.sleep(1.seconds);
    transport.close();
    t2.join();
    assert(sseData.canFind("ping"));
}
