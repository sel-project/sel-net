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
 * Source: $(HTTP github.com/sel-project/sel-net/sel/net/modifiers.d, sel/net/modifiers.d)
 */
module sel.net.modifiers;

import std.bitmanip : _write = write, _read = read;
import std.conv : to;
import std.socket : Socket, Address;
import std.system : Endian;
import std.traits : isNumeric, isIntegral, Parameters;
import std.zlib : Compress, UnCompress;

import sel.net.stream : Stream;

abstract class ModifierStream : Stream {

	public Stream stream;

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

class PaddedStream(size_t paddingIndex) : ModifierStream {

	private ubyte[] padding;

	public this(Stream stream, ubyte[] padding) {
		super(stream);
	}

	public override ptrdiff_t send(ubyte[] payload) {
		static if(paddingIndex == 0) {
			payload = this.padding ~ payload;
		} else {
			payload = payload[0..paddingIndex] ~ this.padding ~ payload[paddingIndex..$];
		}
		return super.send(payload);
	}

	public override ubyte[] receive() {
		ubyte[] payload = super.receive();
		if(payload.length >= this.padding.length + paddingIndex) {
			static if(paddingIndex == 0) {
				return payload[this.padding.length..$];
			} else {
				return payload[0..this.padding.length] ~ payload[this.padding.length..$];
			}
		}
		return [];
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
			immutable length = payload.length.to!T;
			payload = new ubyte[requiredSize] ~ payload;
			_write!(T, endianness)(payload, length, 0);
		} else {
			payload = T.encode(payload.length.to!(Parameters!(T.encode)[0])) ~ payload;
		}
		return super.send(payload);
	}
	
	/**
	 * Returns: an array of bytes as indicated by the length or an empty array on failure or when the indicated length exceeds the max length
	 */
	public override ubyte[] receive() {
		return this.receiveImpl();
	}
	
	private ubyte[] receiveImpl() {
		if(this.nextLength == 0) {
			// read length of the packet
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
			// read the packet with the given length
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
		ubyte[] recv = super.receive();
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
