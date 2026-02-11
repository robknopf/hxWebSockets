package hx.ws;

class WebSocketHandler extends Handler {
    public static var MAX_WAIT_TIME:Int = 1000; // if no handshake has happened after this time (in seconds), we'll consider it dead and disconnect
    
    private var _creationTime:Float;
    
    public function new(socket:SocketImpl) {
        super(socket);
        _creationTime = Sys.time();
        _socket.setBlocking(false);
        Log.debug('New socket handler', id);
    }

    public override function handle() {
        if (this.state == State.Handshake && Sys.time() - _creationTime > (MAX_WAIT_TIME / 1000)) {
            Log.info('No handshake detected in ${MAX_WAIT_TIME}ms, closing connection', id);
            this.close();
            return;
        }
        super.handle();
    }
    
    private override function handleData() {
        switch (state) {
            case State.Handshake:
                var httpRequest = recvHttpRequest();
                if (httpRequest == null) {
                    return;
                }

                handshake(httpRequest);
                handleData();
            case _:
                super.handleData();
        }
    }

    public function handshake(httpRequest:HttpRequest) {
        var httpResponse = new HttpResponse();
        function reqHeader(name:String):Null<String> {
            var exact = httpRequest.headers.get(name);
            if (exact != null) {
                return exact;
            }
            var lower = name.toLowerCase();
            for (k in httpRequest.headers.keys()) {
                if (k != null && k.toLowerCase() == lower) {
                    return httpRequest.headers.get(k);
                }
            }
            return null;
        }

        httpResponse.headers.set(HttpHeader.SEC_WEBSOCKET_VERSION, "13");
        if (httpRequest.method != "GET" || httpRequest.httpVersion != "HTTP/1.1") {
            httpResponse.code = 400;
            httpResponse.text = "Bad";
            httpResponse.headers.set(HttpHeader.CONNECTION, "close");
            httpResponse.headers.set(HttpHeader.X_WEBSOCKET_REJECT_REASON, 'Bad request');
        } else if (reqHeader(HttpHeader.SEC_WEBSOCKET_VERSION) != "13") {
            httpResponse.code = 426;
            httpResponse.text = "Upgrade";
            httpResponse.headers.set(HttpHeader.CONNECTION, "close");
            httpResponse.headers.set(HttpHeader.X_WEBSOCKET_REJECT_REASON, 'Unsupported websocket client version: ${reqHeader(HttpHeader.SEC_WEBSOCKET_VERSION)}, Only version 13 is supported.');
        } else if (reqHeader(HttpHeader.UPGRADE) == null || reqHeader(HttpHeader.UPGRADE).toLowerCase() != "websocket") {
            httpResponse.code = 426;
            httpResponse.text = "Upgrade";
            httpResponse.headers.set(HttpHeader.CONNECTION, "close");
            httpResponse.headers.set(HttpHeader.X_WEBSOCKET_REJECT_REASON, 'Unsupported upgrade header: ${reqHeader(HttpHeader.UPGRADE)}.');
        } else if (reqHeader(HttpHeader.CONNECTION) == null || reqHeader(HttpHeader.CONNECTION).toLowerCase().indexOf("upgrade") == -1) {
            httpResponse.code = 426;
            httpResponse.text = "Upgrade";
            httpResponse.headers.set(HttpHeader.CONNECTION, "close");
            httpResponse.headers.set(HttpHeader.X_WEBSOCKET_REJECT_REASON, 'Unsupported connection header: ${reqHeader(HttpHeader.CONNECTION)}.');
        } else {
            Log.debug('Handshaking', id);
            var key = reqHeader(HttpHeader.SEC_WEBSOCKET_KEY);
            var result = makeWSKeyResponse(key);
            Log.debug('Handshaking key - ${result}', id);

            httpResponse.code = 101;
            httpResponse.text = "Switching Protocols";
            httpResponse.headers.set(HttpHeader.UPGRADE, "websocket");
            httpResponse.headers.set(HttpHeader.CONNECTION, "Upgrade");
            httpResponse.headers.set(HttpHeader.SEC_WEBSOCKET_ACCEPT, result);
        }
        
        function callback(httpResponse: HttpResponse) {
            sendHttpResponse(httpResponse);

            if (httpResponse.code == 101) {
                _onopenCalled = false;
                state = State.Head;
                Log.debug('Connected', id);
            } else {
                close();
            }
        }
        
        if (validateHandshake != null) {
            validateHandshake(httpRequest, httpResponse, callback);
        } else {
            callback(httpResponse);
        }
    }
}
