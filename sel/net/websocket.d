/*
 * Copyright (c) 2018 SEL
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
/**
 * Copyright: 2017-2018 sel-project
 * License: LGPL-3.0
 * Authors: Kripth
 * Source: $(HTTP github.com/sel-project/sel-net/sel/net/websocket.d, sel/net/websocket.d)
 */
module sel.net.websocket;

import std.base64 : Base64;
import std.bitmanip : nativeToBigEndian, bigEndianToNative;
import std.conv : to;
import std.digest.sha : sha1Of;
import std.socket : Socket;

import sel.net.http : StatusCodes, Request, Response;
import sel.net.modifiers : ModifierStream;
import sel.net.stream : Stream, TcpStream;

private enum magicString = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

public Response authWebSocketClient(Request request) {
	Response response;
	auto key = "sec-websocket-key" in request.headers;
	if(key) {
		response = Response(StatusCodes.switchingProtocols, [
			"Sec-WebSocket-Accept": Base64.encode(sha1Of(*key ~ magicString)).idup,
			"Connection": "upgrade",
			"Upgrade": "websocket"
		]);
		response.valid = true;
	}
	return response;
}

/**
 * Example:
 * ---
 * auto wss = new WebSocketServerStream(new TcpStream(socket));
 * ---
 */
class WebSocketServerStream : ModifierStream {

	public this(Stream stream) {
		super(stream);
	}
	
	public override ptrdiff_t send(ubyte[] payload) {
		ubyte[] header = [0b10000001];
		if(payload.length < 0b01111110) {
			header ~= payload.length & 255;
		} else if(payload.length < ushort.max) {
			header ~= 0b01111110;
			header ~= nativeToBigEndian(cast(ushort)payload.length);
		} else {
			header ~= 0b01111111;
			header ~= nativeToBigEndian(cast(ulong)payload.length);
		}
		return this.stream.send(header ~ payload);
	}
	
	public ptrdiff_t send(string payload) {
		return this.send(cast(ubyte[])payload);
	}
	
	public override ubyte[] receive() {
		ubyte[] payload = this.stream.receive();
		if(payload.length > 2 && (payload[0] & 0b1111) == 1) {
			bool masked = (payload[1] & 0b10000000) != 0;
			size_t length = payload[1] & 0b01111111;
			size_t index = 2;
			if(length == 0b01111110) {
				if(payload.length >= index + 2) {
					ubyte[2] bytes = payload[index..index+2];
					length = bigEndianToNative!ushort(bytes);
					index += 2;
				}
			} else if(length == 0b01111111) {
				if(payload.length >= index + 8) {
					ubyte[8] bytes = payload[index..index+8];
					length = bigEndianToNative!ulong(bytes).to!size_t;
					length += 8;
				}
			}
			if(payload.length >= index + length) {
				if(!masked) {
					return payload[index..index+length];
				} else if(payload.length == index + length + 4) {
					immutable index4 = index + 4;
					ubyte[4] mask = payload[index..index4];
					payload = payload[index4..index4+length];
					foreach(i, ref ubyte p; payload) {
						p ^= mask[i % 4];
					}
					return payload;
				}
			}
		}
		return (ubyte[]).init;
	}
	
}
