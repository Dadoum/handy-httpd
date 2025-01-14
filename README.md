# handy-httpd

An extremely lightweight HTTP server for the [D programming language](https://dlang.org/).

[Check out the full documentation here.](https://andrewlalis.github.io/handy-httpd/)

## Features
- HTTP/1.1
- Worker pool for request handling
- Simple configuration
- High performance (low GC usage)
- Beginner friendly
- Extensible with custom handlers, exception handlers, and filters
- Well-documented
- Ships with some handy pre-made request handlers:
	- Serve static files with the `FileResolvingHandler`
	- Apply filters before and after handling requests with the `FilteredHandler`
	- Handle complex URL paths, including path parameters and wildcards, with the `PathDelegatingHandler`

## Simple Example
In this example, we take advantage of the [Dub package manager](https://code.dlang.org/)'s single-file SDL syntax to declare HandyHttpd as a dependency. For this example, we'll call this `my_server.d`.
```d
#!/usr/bin/env dub
/+ dub.sdl:
	dependency "handy_httpd" version="~>5.2"
+/
import handy_httpd;

void main() {
	new HttpServer((ref ctx) {
		if (ctx.request.url == "/hello") {
			response.writeBodyString("Hello world!");
		} else {
			response.notFound();
		}
	}).start();
}
```
To start the server, just mark the script as executable, and run it:

```shell
chmod +x my_server.d
./my_server.d
```

And finally, if you navigate to http://localhost:8080/hello, you should see the `Hello world!` text appear.
