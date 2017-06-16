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
module sel.stream.stream;

import std.socket : Socket, Address;

class Stream {
	
	public Socket socket;
	protected ptrdiff_t last_recv = -1;

	public this(Socket socket) {
		this.socket = socket;
	}
	
	public abstract ptrdiff_t send(ubyte[] buffer);
	
	public abstract ubyte[] receive();

	public pure nothrow @property @safe @nogc ptrdiff_t lastRecv() {
		return this.last_recv;
	}
	
}

class TcpStream : Stream {

	private ubyte[] buffer;

	public this(Socket socket, size_t bufferSize=4096) {
		super(socket);
		this.buffer = new ubyte[bufferSize];
	}

	public override ptrdiff_t send(ubyte[] payload) {
		size_t sent = 0;
		while(sent < payload.length) {
			auto s = this.socket.send(payload[sent..$]);
			if(s <= 0) return sent;
			sent += s;
		}
		return sent;
	}

	public override ubyte[] receive() {
		this.last_recv = this.socket.receive(buffer);
		if(this.last_recv > 0) {
			return this.buffer[0..this.last_recv].dup;
		} else {
			return [];
		}
	}

}

class UdpStream : Stream {

	private Address address;
	private ubyte[] buffer;

	public this(Socket socket, Address address=null, size_t bufferSize=1492) {
		super(socket);
		this.buffer = new ubyte[bufferSize];
	}

	public override ptrdiff_t send(ubyte[] buffer) {
		return this.socket.sendTo(buffer, this.address);
	}

	public ptrdiff_t sendTo(ubyte[] buffer, Address address) {
		return this.socket.sendTo(buffer, address);
	}

	public override ubyte[] receive() {
		this.last_recv = this.socket.receiveFrom(this.buffer, this.address);
		if(this.last_recv > 0) {
			return this.buffer[0..this.last_recv].dup;
		} else {
			return [];
		}
	}

	public ubyte[] receiveFrom(ref Address address) {
		this.last_recv = this.socket.receiveFrom(this.buffer, address);
		if(this.last_recv > 0) {
			return this.buffer[0..this.last_recv].dup;
		} else {
			return [];
		}
	}

}
