/*
 * Copyright (c) 2017 SEL
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

import std.conv : to, ConvException;
import std.socket : Socket;
import std.string : join, split, toUpper, toLower, strip;

import sel.net.stream : Stream, TcpStream;

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
 * HTTP status codes and their human-readable names.
 */
enum string[uint] statusCodes = [

	// informational
	100: "Continue",
	101: "Switching Protocols",
	102: "Processing",

	// success
	200: "OK",
	201: "Created",
	202: "Accepted",
	203: "Non-Authoritative Information",
	204: "No Content",
	205: "Reset Content",
	206: "Partial Content",

	// redirection
	300: "Multiple Choices",
	301: "Moved Permanently",
	302: "Found",
	303: "See Other",
	304: "Not Modified",
	305: "Use Proxy",
	306: "Switch Proxy",
	307: "Temporary Redirect",

	// client errors
	400: "Bad Request",
	401: "Unauthorized",
	402: "Payment Required",
	403: "Forbidden",
	404: "Not Found",
	405: "Method Not Allowed",
	406: "Not Acceptable",

	// server errors
	500: "Internal Server Error",
	501: "Not Implemented",
	502: "Bad Gateway",
	503: "Service Unavailable",
	504: "Gateway Timeout",
	505: "HTTP Version Not Supported",

];

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
	 * auto post = Request.post("/sub.php", ["Connection": "Close"], "name=Mark&surname=White");
	 * assert(post.toString() == "POST /sub.php HTTP/1.1\r\nConnection: Close\r\n\r\nname=Mark&surname=White");
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
	 * auto request = Request(Request.GET, "index.html", ["Connection": "Close"]);
	 * assert(request.toString() == "GET /index.html HTTP/1.1\r\nConnection: Close\r\n");
	 * ---
	 */
	public string toString() {
		return encodeHTTP(this.method.toUpper() ~ " " ~ this.path ~ " HTTP/1.1", this.headers, this.data);
	}

	/**
	 * Parses a string and returns a Request.
	 * If the request is successfully parsed Request.valid will be true.
	 * Example:
	 * ---
	 * auto request = Request.parse("GET /index.html HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: Close");
	 * assert(request.valid);
	 * assert(request.method == Request.GET);
	 * assert(request.headers["Host"] == "127.0.0.1");
	 * assert(request.headers["Connection"] == "Close");
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
 */
struct Response {
	
	uint statusCode;
	string statusMessage;
	
	string[string] headers;
	
	string content;

	bool valid;
	
	public this(uint statusCode, string statusMessage, string[string] headers=defaultHeaders, string content="") {
		this.statusCode = statusCode;
		this.statusMessage = statusMessage;
		this.headers = headers;
		this.content = content;
	}
		
	public this(uint statusCode, string[string] headers=defaultHeaders, string content="") {
		this(statusCode, statusCodes.get(statusCode, "Unknown Status Code"), headers, content);
	}

	public string toString() {
		this.headers["Content-Length"] = to!string(this.content.length);
		return encodeHTTP("HTTP/1.1 " ~ this.statusCode.to!string ~ " " ~ this.statusMessage, this.headers, this.content);
	}

	public static Response parse(string str) {
		Response response;
		string status;
		if(decodeHTTP(str, status, response.headers, response.content)) {
			string[] head = status.split(" ");
			if(head.length >= 3) {
				try {
					response.statusCode = to!uint(head[1]);
					response.statusMessage = join(head[2..$], " ");
					response.valid = true;
				} catch(ConvException) {}
			}
		}
		return response;
	}
	
}

private string encodeHTTP(string status, string[string] headers, string content) {
	string[] ret = [status];
	foreach(key, value; headers) {
		ret ~= key ~ ": " ~ value;
	}
	ret ~= "";
	if(content.length) ret ~= content;
	return join(ret, "\r\n");
}

private bool decodeHTTP(string str, ref string status, ref string[string] headers, ref string content) {
	string[] spl = str.split("\r\n");
	if(spl.length > 1) {
		status = spl[0];
		size_t index;
		while(++index < spl.length && spl[index].length) { // read until empty line
			auto s = spl[index].split(":");
			if(s.length >= 2) {
				headers[s[0].strip] = s[1..$].join(":").strip;
			} else {
				return false; // invalid header
			}
		}
		content = join(spl[index..$], "\r\n");
		return true;
	} else {
		return false;
	}
}
