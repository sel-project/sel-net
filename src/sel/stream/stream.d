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

	public this(Socket socket) {
		this.socket = socket;
	}
	
	public abstract ptrdiff_t send(ubyte[] buffer);
	
	public abstract ubyte[] receive();
	
}

class TcpStream : Stream {

	private ubyte[] buffer;

	public this(Socket socket, size_t bufferSize=4096) {
		super(socket);
		this.buffer = new ubyte[bufferSize];
	}

	public override ptrdiff_t send(ubyte[] payload) {
		return this.socket.send(payload); //TODO send unless the return is equals to payload.length or -1
	}

	public ubyte[] receive(ref bool closed) {
		auto recv = this.socket.receive(buffer);
		if(recv >= 0) {
			return this.buffer[0..recv].dup;
		} else if(recv == 0) {
			closed = true;
		}
		return [];
	}

	public override ubyte[] receive() {
		bool closed;
		return this.receive(closed);
	}

}

class UdpStream : Stream {

	private Address address;
	private ubyte[] buffer;

	public this(Socket socket, Address address, size_t bufferSize=1492) {
		super(socket);
		this.buffer = new ubyte[bufferSize];
	}

	public override ptrdiff_t send(ubyte[] buffer) {
		return this.socket.sendTo(buffer, this.address);
	}

	public override ubyte[] receive() {
		auto recv = this.socket.receiveFrom(this.buffer, this.address);
		if(recv > 0) {
			return this.buffer[0..recv].dup;
		} else {
			return [];
		}
	}

}
