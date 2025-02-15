/** 
 * This module contains the logic for each server worker, which involves
 * parsing and handling incoming requests.
 */
module handy_httpd.components.worker;

import std.socket;
import std.typecons;
import std.conv;
import core.thread;
import std.datetime;
import std.datetime.stopwatch;
import httparsed : MsgParser, initParser;

import handy_httpd.server;
import handy_httpd.components.handler;
import handy_httpd.components.request;
import handy_httpd.components.response;
import handy_httpd.components.logger;
import handy_httpd.components.parse_utils;
import handy_httpd.util.range;

/** 
 * The server worker thread is a thread that processes incoming requests from
 * an `HttpServer`.
 */
class ServerWorkerThread : Thread {
    private const(int) id;
    private MsgParser!Msg requestParser = initParser!Msg();
    private ubyte[] receiveBuffer;
    private HttpServer server;
    private ContextLogger log;

    /** 
     * Constructs this worker thread for the given server, with the given id.
     * Params:
     *   server = The server that this thread belongs to.
     *   id = The thread's id.
     */
    this(HttpServer server, int id) {
        super(&run);
        super.name("handy-httpd_worker-" ~ id.to!string);
        this.id = id;
        this.receiveBuffer = new ubyte[server.config.receiveBufferSize];
        this.server = server;
        this.log = ContextLogger(this.name, server.config.serverLogLevel);
    }

    /** 
     * Runs the worker thread. This will run continuously until the server
     * stops. The worker will do the following:
     * 
     * 1. Wait for the next available client.
     * 2. Parse the HTTP request from the client.
     * 3. Handle the request using the server's handler.
     */
    private void run() {
        while (server.isReady) {
            // First try and get a socket to the client.
            Nullable!Socket nullableSocket = server.waitForNextClient();
            if (nullableSocket.isNull) continue;
            Socket clientSocket = nullableSocket.get();

            StopWatch sw = StopWatch(AutoStart.yes);

            // Then try and parse their request and obtain a request context.
            Nullable!HttpRequestContext nullableCtx = receiveRequest(clientSocket);
            if (nullableCtx.isNull) continue;
            HttpRequestContext ctx = nullableCtx.get();

            // Then handle the request using the server's handler.
            log.infoF!"%s %s"(ctx.request.method, ctx.request.url);
            try {
                this.server.getHandler.handle(ctx);
                if (!ctx.response.isFlushed) {
                    ctx.response.flushHeaders();
                }
            } catch (Exception e) {
                this.server.getExceptionHandler.handle(ctx, e);
            }
            clientSocket.shutdown(SocketShutdown.BOTH);
            clientSocket.close();

            sw.stop();
            log.infoF!"%d %s (took %d μs)"(ctx.response.status, ctx.response.statusText, sw.peek.total!"usecs");

            // Reset the request parser so we're ready for the next request.
            requestParser.msg.reset();
            
            // Destroy the request context's allocated objects.
            destroy!(false)(ctx.request.inputRange);
            destroy!(false)(ctx.response.outputRange);
        }
    }

    /** 
     * Attempts to receive an HTTP request from the given socket.
     * Params:
     *   clientSocket = The socket to receive from.
     * Returns: A nullable request context, which if present, can be used to
     * further handle the request. If null, no further action should be taken
     * beyond closing the socket.
     */
    private Nullable!HttpRequestContext receiveRequest(Socket clientSocket) {
        Nullable!HttpRequestContext result;
        size_t received = clientSocket.receive(receiveBuffer);
        if (received == 0 || received == Socket.ERROR) {
            if (received == 0) {
                log.infoF!"Client %s closed the connection before a request was sent."(clientSocket.remoteAddress);
            } else if (received == Socket.ERROR) {
                log.errorF!"Socket receive failed. Received %d."(received);
            }
            clientSocket.close();
            return result; // Skip if we didn't receive valid data.
        }
        immutable ubyte[] data = receiveBuffer[0..received].idup;

        // Prepare the request context by parsing the HttpRequest, and preparing the context.
        try {
            auto requestAndSize = handy_httpd.components.parse_utils.parseRequest(requestParser, cast(string) data);
            result = prepareRequestContext(requestAndSize[0], requestAndSize[1], received, clientSocket);
            return result;
        } catch (Exception e) {
            log.warnF!"Failed to parse HTTP request: %s"(e.msg);
            clientSocket.close();
            return result;
        }
    }

    /** 
     * Helper method to build the request context from the basic components
     * obtained from parsing a request.
     * Params:
     *   parsedRequest = The parsed request.
     *   bytesRead = The number of bytes read during request parsing.
     *   bytesReceived = The number of bytes initially received.
     *   socket = The socket that connected.
     * Returns: A request context that is ready handling.
     */
    private HttpRequestContext prepareRequestContext(
        HttpRequest parsedRequest,
        size_t bytesRead,
        size_t bytesReceived,
        Socket socket
    ) {
        HttpRequestContext ctx = HttpRequestContext(
            parsedRequest,
            HttpResponse(),
            this.server,
            this,
            ContextLogger.forWorkerThread(this)
        );
        ctx.request.inputRange = new SocketInputRange(socket, getReceiveBuffer(), bytesRead, bytesReceived);
        ctx.response.outputRange = new SocketOutputRange(socket);
        foreach (headerName, headerValue; this.server.config.defaultHeaders) {
            ctx.response.addHeader(headerName, headerValue);
        }
        return ctx;
    }

    /** 
     * Gets this worker's id.
     * Returns: The worker id.
     */
    public int getId() {
        return id;
    }

    /** 
     * Gets a pointer to this worker's internal pre-allocated receive buffer.
     * Returns: A pointer to the worker's receive buffer.
     */
    public ubyte[]* getReceiveBuffer() {
        return &receiveBuffer;
    }

    /** 
     * Gets the server that this worker was created for.
     * Returns: The server.
     */
    public HttpServer getServer() {
        return server;
    }
}