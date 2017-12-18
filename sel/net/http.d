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

import std.conv : to;
import std.string : join, split, toUpper, toLower, strip;

import sel.net.stream : Stream;

enum string[uint] codes = [

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

private enum defaultHeaders = ["Server": "sel-net/0.0.1"]; //TODO load version from .git

struct Request {
	
	string method;
	string path;
	
	string[string] headers;
	
	bool valid;

	public this(string method, string path, string[string] headers=defaultHeaders) {
		this.method = method;
		this.path = path;
		this.headers = headers;
	}
	
	public string toString() {
		return join([this.method.toUpper() ~ " " ~ path ~ " HTTP/1.1"] ~ encodeHeaders(this.headers), "\r\n");
	}
	
	public static Request parse(string str) {
		Request request;
		string[] spl = str.split("\r\n");
		if(spl.length > 0) {
			string[] head = spl[0].split(" ");
			if(head.length == 3) {
				request.valid = true;
				request.method = head[0];
				request.path = head[1];
				request.headers = decodeHeaders(spl[1..$]);
			}
		}
		return request;
	}
	
}

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
		this(statusCode, codes.get(statusCode, "Unknown Status Code"), headers, content);
	}

	public string toString() {
		this.headers["Content-Length"] = to!string(this.content.length);
		return join(["HTTP/1.1 " ~ this.statusCode.to!string ~ " " ~ this.statusMessage] ~ encodeHeaders(this.headers) ~ ["", this.content], "\r\n");
	}

	public static Response parse(string str) {
		Response response;
		string[] content = str.split("\r\n\r\n");
		if(content.length) {
			string[] spl = content[0].split("\r\n");
			if(spl.length > 0) {
				string[] head = spl[0].split(" ");
				if(head.length == 3) {
					try {
						response.statusCode = to!uint(head[1]);
						response.statusMessage = head[2];
						response.valid = true;
						response.headers = decodeHeaders(spl[1..$]);
						if(content.length >= 2) {
							response.content = content[1..$].join("\r\n\r\n");
						}
					} catch(Exception) {}
				}
			}
		}
		return response;
	}
	
}

private string[] encodeHeaders(string[string] headers) {
	string[] ret;
	foreach(key, value; headers) {
		ret ~= key ~ ": " ~ value;
	}
	return ret;
}

private string[string] decodeHeaders(string[] headers) {
	string[string] ret;
	foreach(header ; headers) {
		auto s = header.split(":");
		if(s.length >= 2) {
			ret[s[0].strip] = s[1..$].join(":").strip;
		}
	}
	return ret;
}
