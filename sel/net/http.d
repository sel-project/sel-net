/*
 * Copyright (c) 2017-2018 SEL
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU Lesser General Public License for more details.
 * 
 */
module sel.net.http;

import std.array : Appender;
import std.conv : to, ConvException;
import std.socket : Socket;
import std.string : join, split, toUpper, toLower, strip;
import std.traits : EnumMembers;

import sel.net.stream : Stream, TcpStream;

/**
 * Stream container for HTTP connection that reads/writes strings
 * instead of array of bytes.
 */
class HttpStream {

	private Stream stream;

	public this(Stream stream) {
		this.stream = stream;
	}

	public this(Socket socket) {
		this(new TcpStream(socket));
	}

	public ptrdiff_t send(string payload) {
		return this.stream.send(cast(ubyte[])payload);
	}

	public string receive() {
		return cast(string)this.stream.receive();
	}

}

/**
 * Indicates the status of an HTTP response.
 */
struct Status {

	/**
	 * HTTP response status code.
	 */
	uint code;

	/**
	 * Additional short description of the status code.
	 */
	string message;

	bool opEquals(uint code) {
		return this.code == code;
	}

	bool opEquals(Status status) {
		return this.opEquals(status.code);
	}

	/**
	 * Concatenates the status code and the message into
	 * a string.
	 * Example:
	 * ---
	 * assert(Status(200, "OK").toString() == "200 OK");
	 * ---
	 */
	string toString() {
		return this.code.to!string ~ " " ~ this.message;
	}

	/**
	 * Creates a status from a known list of codes/messages.
	 * Example:
	 * ---
	 * assert(Status.get(200).message == "OK");
	 * ---
	 */
	public static Status get(uint code) {
		foreach(statusCode ; [EnumMembers!StatusCodes]) {
			if(code == statusCode.code) return statusCode;
		}
		return Status(code, "Unknown Status Code");
	}

}

/**
 * HTTP status codes and their human-readable names.
 */
enum StatusCodes : Status {

	// informational
	continue_ = Status(100, "Continue"),
	switchingProtocols = Status(101, "Switching Protocols"),

	// success
	ok = Status(200, "OK"),
	created = Status(201, "Created"),
	accepted = Status(202, "Accepted"),
	nonAuthoritativeContent = Status(203, "Non-Authoritative Information"),
	noContent = Status(204, "No Content"),
	resetContent = Status(205, "Reset Content"),
	partialContent = Status(206, "Partial Content"),

	// redirection
	multipleChoices = Status(300, "Multiple Choices"),
	movedPermanently = Status(301, "Moved Permanently"),
	found = Status(302, "Found"),
	seeOther = Status(303, "See Other"),
	notModified = Status(304, "Not Modified"),
	useProxy = Status(305, "Use Proxy"),
	switchProxy = Status(306, "Switch Proxy"),
	temporaryRedirect = Status(307, "Temporary Redirect"),
	permanentRedirect = Status(308, "Permanent Redirect"),

	// client errors
	badRequest = Status(400, "Bad Request"),
	unauthorized = Status(401, "Unauthorized"),
	paymentRequired = Status(402, "Payment Required"),
	forbidden = Status(403, "Forbidden"),
	notFound = Status(404, "Not Found"),
	methodNotAllowed = Status(405, "Method Not Allowed"),
	notAcceptable = Status(406, "Not Acceptable"),
	proxyAuthenticationRequired = Status(407, "Proxy Authentication Required"),
	requestTimeout = Status(408, "Request Timeout"),
	conflict = Status(409, "Conflict"),
	gone = Status(410, "Gone"),
	lengthRequired = Status(411, "Length Required"),
	preconditionFailed = Status(412, "Precondition Failed"),
	payloadTooLarge = Status(413, "Payload Too Large"),
	uriTooLong = Status(414, "URI Too Long"),
	unsupportedMediaType = Status(415, "UnsupportedMediaType"),
	rangeNotSatisfiable = Status(416, "Range Not Satisfiable"),
	expectationFailed = Status(417, "Expectation Failed"),

	// server errors
	internalServerError = Status(500, "Internal Server Error"),
	notImplemented = Status(501, "Not Implemented"),
	badGateway = Status(502, "Bad Gateway"),
	serviceUnavailable = Status(503, "Service Unavailable"),
	gatewayTimeout = Status(504, "Gateway Timeout"),
	httpVersionNotSupported = Status(505, "HTTP Version Not Supported"),

}

private enum defaultHeaders = ["Server": "sel-net/1.0"]; //TODO load version from .dub/version.json

/**
 * Container for a HTTP request.
 * Example:
 * ---
 * Request("GET", "/");
 * Request(Request.POST, "/subscribe.php");
 */
struct Request {

	enum GET = "GET";
	enum POST = "POST";

	/**
	 * Method used in the request (i.e. GET). Must be uppercase.
	 */
	string method;

	/**
	 * Path of the request. It should start with a slash.
	 */
	string path;

	/**
	 * HTTP headers of the request.
	 */
	string[string] headers;

	/**
	 * Optional raw form data, for POST requests.
	 */
	string data;

	/**
	 * If the request was parsed, indicates whether it was in a
	 * valid HTTP format.
	 */
	bool valid;

	public this(string method, string path, string[string] headers=defaultHeaders) {
		this.method = method;
		this.path = path;
		this.headers = headers;
	}

	/**
	 * Creates a get request.
	 * Example:
	 * ---
	 * auto get = Request.get("/index.html", ["Host": "127.0.0.1"]);
	 * assert(get.toString() == "GET /index.html HTTP/1.1\r\nHost: 127.0.0.1\r\n");
	 * ---
	 */
	public static Request get(string path, string[string] headers=defaultHeaders) {
		return Request(GET, path, headers);
	}

	/**
	 * Creates a post request.
	 * Example:
	 * ---
	 * auto post = Request.post("/sub.php", ["Connection": "Keep-Alive"], "name=Mark&surname=White");
	 * assert(post.toString() == "POST /sub.php HTTP/1.1\r\nConnection: Keep-Alive\r\n\r\nname=Mark&surname=White");
	 * ---
	 */
	public static Request post(string path, string[string] headers=defaultHeaders, string data="") {
		Request request = Request(POST, path, headers);
		request.data = data;
		return request;
	}

	/// ditto
	public static Request post(string path, string data, string[string] headers=defaultHeaders) {
		return post(path, headers, data);
	}

	/**
	 * Encodes the request into a string.
	 * Example:
	 * ---
	 * auto request = Request(Request.GET, "index.html", ["Connection": "Keep-Alive"]);
	 * assert(request.toString() == "GET /index.html HTTP/1.1\r\nConnection: Keep-Alive\r\n");
	 * ---
	 */
	public string toString() {
		if(this.data.length) this.headers["Content-Length"] = to!string(this.data.length);
		return encodeHTTP(this.method.toUpper() ~ " " ~ this.path ~ " HTTP/1.1", this.headers, this.data);
	}

	/**
	 * Parses a string and returns a Request.
	 * If the request is successfully parsed Request.valid will be true.
	 * Please note that every key in the header is converted to lowercase for
	 * an easier search in the associative array.
	 * Example:
	 * ---
	 * auto request = Request.parse("GET /index.html HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: Keep-Alive\r\n");
	 * assert(request.valid);
	 * assert(request.method == Request.GET);
	 * assert(request.headers["Host"] == "127.0.0.1");
	 * assert(request.headers["Connection"] == "Keep-Alive");
	 * ---
	 */
	public static Request parse(string str) {
		Request request;
		string status;
		if(decodeHTTP(str, status, request.headers, request.data)) {
			string[] spl = status.split(" ");
			if(spl.length == 3) {
				request.valid = true;
				request.method = spl[0];
				request.path = spl[1];
			}
		}
		return request;
	}
	
}

/**
 * Container for an HTTP response.
 * Example:
 * ---
 * Response(200, ["Connection": "Close"], "<b>Hi there</b>");
 * Response(404, [], "Cannot find the specified path");
 * Response(204);
 * ---
 */
struct Response {

	/**
	 * Status of the response.
	 */
	Status status;

	/**
	 * HTTP headers of the request.
	 */
	string[string] headers;

	/**
	 * Content of the request. Its type should be specified in
	 * the `content-type` field in the headers.
	 */
	string content;

	/**
	 * If the response was parsed, indicates whether it was in a
	 * valid HTTP format.
	 */
	bool valid;
	
	public this(Status status, string[string] headers=defaultHeaders, string content="") {
		this.status = status;
		this.headers = headers;
		this.content = content;
	}
		
	public this(uint statusCode, string[string] headers=defaultHeaders, string content="") {
		this(Status.get(statusCode), headers, content);
	}

	public this(Status status, string content) {
		this(status, defaultHeaders, content);
	}

	public this(uint statusCode, string content) {
		this(statusCode, defaultHeaders, content);
	}

	/**
	 * Creates a response for an HTTP error an automatically generates
	 * an HTML page to display it.
	 * Example:
	 * ---
	 * Response.error(404);
	 * Response.error(StatusCodes.methodNotAllowed, ["Allow": "GET"]);
	 * ---
	 */
	public static Response error(Status status, string[string] headers=defaultHeaders) {
		immutable message = status.toString();
		headers["Content-Type"] = "text/html";
		return Response(status, headers, "<!DOCTYPE html><html><head><title>" ~ message ~ "</title></head><body><center><h1>" ~ message ~ "</h1></center><hr><center>" ~ headers.get("Server", "sel-net") ~ "</center></body></html>");
	}

	/// ditto
	public static Response error(uint statusCode, string[string] headers=defaultHeaders) {
		return error(Status.get(statusCode), headers);
	}

	/**
	 * Creates a 3xx redirect response and adds the `Location` field to
	 * the header.
	 * If not specified status code `301 Moved Permanently` will be used.
	 * Example:
	 * ---
	 * Response.redirect("/index.html");
	 * Response.redirect(302, "/view.php");
	 * Response.redirect(StatusCodes.seeOther, "/icon.png", ["Server": "sel-net"]);
	 * ---
	 */
	public static Response redirect(Status status, string location, string[string] headers=defaultHeaders) {
		headers["Location"] = location;
		return Response(status, headers);
	}

	/// ditto
	public static Response redirect(uint statusCode, string location, string[string] headers=defaultHeaders) {
		return redirect(Status.get(statusCode), location, headers);
	}

	/// ditto
	public static Response redirect(string location, string[string] headers=defaultHeaders) {
		return redirect(StatusCodes.movedPermanently, location, headers);
	}

	/**
	 * Encodes the response into a string.
	 * The `Content-Length` header field is created automatically
	 * based on the length of the content field.
	 * Example:
	 * ---
	 * auto response = Response(200, [], "Hi");
	 * assert(response.toString() == "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nHi");
	 * ---
	 */
	public string toString() {
		this.headers["Content-Length"] = to!string(this.content.length);
		return encodeHTTP("HTTP/1.1 " ~ this.status.toString(), this.headers, this.content);
	}

	/**
	 * Parses a string and returns a Response.
	 * If the response is successfully parsed Response.valid will be true.
	 * Please note that every key in the header is converted to lowercase for
	 * an easier search in the associative array.
	 * Example:
	 * ---
	 * auto response = Response.parse("HTTP/1.1 200 OK\r\nContent-Type: plain/text\r\nContent-Length: 4\r\n\r\ntest");
	 * assert(response.valid);
	 * assert(response.status == 200);
	 * assert(response.headers["content-type"] == "text/plain");
	 * assert(response.headers["content-length"] == "4");
	 * assert(response.content == "test");
	 * ---
	 */
	public static Response parse(string str) {
		Response response;
		string status;
		if(decodeHTTP(str, status, response.headers, response.content)) {
			string[] head = status.split(" ");
			if(head.length >= 3) {
				try {
					response.status = Status(to!uint(head[1]), join(head[2..$], " "));
					response.valid = true;
				} catch(ConvException) {}
			}
		}
		return response;
	}
	
}

private enum CR_LF = "\r\n";

private string encodeHTTP(string status, string[string] headers, string content) {
	Appender!string ret;
	ret.put(status);
	ret.put(CR_LF);
	foreach(key, value; headers) {
		ret.put(key);
		ret.put(": ");
		ret.put(value);
		ret.put(CR_LF);
	}
	ret.put(CR_LF); // empty line
	ret.put(content);
	return ret.data;
}

private bool decodeHTTP(string str, ref string status, ref string[string] headers, ref string content) {
	string[] spl = str.split(CR_LF);
	if(spl.length > 1) {
		status = spl[0];
		size_t index;
		while(++index < spl.length && spl[index].length) { // read until empty line
			auto s = spl[index].split(":");
			if(s.length >= 2) {
				headers[s[0].strip.toLower()] = s[1..$].join(":").strip;
			} else {
				return false; // invalid header
			}
		}
		content = join(spl[index+1..$], "\r\n");
		return true;
	} else {
		return false;
	}
}
