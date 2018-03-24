/*
 * Copyright (c) 2017-2018 sel-project
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
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
