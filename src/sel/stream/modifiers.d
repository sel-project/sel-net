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
module sel.stream.modifiers;

import std.bitmanip : _write = write, _read = read;
import std.conv : to;
import std.socket : Socket, Address;
import std.system : Endian;
import std.traits : isNumeric, isIntegral, Parameters;
import std.zlib : Compress, UnCompress;

import sel.stream.stream : Stream;

abstract class ModifierStream : Stream {

	protected Stream stream;

	public this(Stream stream) {
		super(stream.socket);
		this.stream = stream;
	}

	public override ptrdiff_t send(ubyte[] buffer) {
		return this.stream.send(buffer);
	}

	public override ubyte[] receive() {
		return this.stream.receive();
	}

	public override pure nothrow @property @safe @nogc ptrdiff_t lastRecv() {
		return this.stream.lastRecv();
	}

}

class LengthPrefixedStream(T, Endian endianness=Endian.bigEndian) : ModifierStream if(isNumeric!T || (is(typeof(T.encode)) && isIntegral!(Parameters!(T.encode)[0]))) {
	
	static if(isNumeric!T) {
		enum requiredSize = T.sizeof;
	} else {
		enum requiredSize = 1;
	}

	public size_t maxLength;

	private ubyte[] next;
	private size_t nextLength = 0;
	
	public this(Stream stream, size_t maxLength=size_t.max) {
		super(stream);
		this.maxLength = maxLength;
	}
	
	/**
	 * Sends a buffer prefixing it with its length.
	 * Returns: the number of bytes sent
	 */
	public override ptrdiff_t send(ubyte[] payload) {
		static if(isNumeric!T) {
			payload = new ubyte[T.length] ~ payload;
			_write!(T, endianness)(payload.length.to!T, payload, 0);
		} else {
			payload = T.encode(payload.length.to!(Parameters!(T.encode)[0])) ~ payload;
		}
		return this.stream.send(payload);
	}
	
	/**
	 * Returns: an array of bytes as indicated by the length or an empty array on failure or when the indicated length exceeds the max length
	 */
	public override ubyte[] receive() {
		return this.receiveImpl();
	}
	
	private ubyte[] receiveImpl() {
		if(this.nextLength == 0) {
			while(this.next.length < requiredSize) {
				if(!this.read()) return [];
			}
			static if(isNumeric!T) {
				this.nextLength = _read!(T, endianness)(this.next);
			} else {
				this.nextLength = T.fromBuffer(this.next);
			}
			if(this.nextLength == 0 || this.nextLength > this.maxLength) {
				// valid connection but unacceptable length
				this.nextLength = 0;
				return [];
			} else {
				return this.receiveImpl();
			}
		} else {
			while(this.next.length < this.nextLength) {
				if(!this.read()) return [];
			}
			ubyte[] ret = this.next[0..this.nextLength];
			this.next = this.next[this.nextLength..$];
			this.nextLength = 0;
			return ret;
		}
	}
	
	/*
	 * Returns: true if some data has been received, false if the connection has been closed or timed out
	 */
	private bool read() {
		ubyte[] recv = this.stream.receive();
		if(this.lastRecv > 0) {
			this.next ~= recv;
			return true;
		} else {
			return false;
		}
	}
	
}

class CompressedStream(T) : ModifierStream {
	
	private immutable size_t thresold;
	
	public this(Stream stream, size_t thresold) {
		super(stream);
		this.thresold = thresold;
	}
	
	public override ptrdiff_t send(ubyte[] buffer) {
		if(buffer.length >= this.thresold) {
			auto compress = new Compress();
			auto data = compress.compress(buffer);
			data ~= compress.flush();
			buffer = T.encode(buffer.length.to!uint) ~ cast(ubyte[])data; //TODO more types
		} else {
			buffer = ubyte.init ~ buffer;
		}
		return super.send(buffer);
	}
	
	public override ubyte[] receive() {
		ubyte[] buffer = super.receive();
		uint length = T.fromBuffer(buffer);
		if(length != 0) {
			// compressed
			auto uncompress = new UnCompress(length);
			buffer = cast(ubyte[])uncompress.uncompress(buffer.dup);
			buffer ~= cast(ubyte[])uncompress.flush();
		}
		return buffer;
	}
	
}
