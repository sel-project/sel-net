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
module sel.stream.raknet;

import std.bitmanip : littleEndianToNative, nativeToLittleEndian, nativeToBigEndian, peek;
import std.socket : Address, Socket;

import sel.stream.stream : Stream;

debug import std.stdio : writeln;

class RaknetStream : Stream {
	
	private Address address;
	public immutable size_t mtu;

	public bool acceptSplit = true;
	private ubyte[][][ushort] splits;
	private size_t[ushort] splitsCount;
	
	private ubyte[] buffer;
	
	private int send_count = 0;
	
	public this(Socket socket, Address address, size_t mtu) {
		super(socket);
		this.address = address;
		this.mtu = mtu;
		this.buffer = new ubyte[mtu + 128];
	}
	
	public override ptrdiff_t send(ubyte[] _buffer) {
		if(_buffer.length > mtu) {
			writeln("buffer is too long!");
			assert(0);
		} else {
			ubyte[] count = nativeToLittleEndian(this.send_count++)[0..3];
			ubyte[] buffer = [ubyte(132)];
			buffer ~= count;
			buffer ~= ubyte(64); // info
			buffer ~= nativeToBigEndian(cast(ushort)(_buffer.length * 8));
			buffer ~= count; // message index
			buffer ~= _buffer;
			return this.socket.sendTo(buffer, this.address);
		}
	}
	
	public override ubyte[] receive() {
		auto recv = this.socket.receiveFrom(this.buffer, this.address);
		if(recv > 0) {
			return this.handle(this.buffer[0..recv]);
		} else {
			return [];
		}
	}

	public ubyte[] handle(ubyte[] buffer) {
		if(buffer.length) {
			switch(buffer[0]) {
				case 192:
					//TODO remove from the waiting_ack queue
					return receive();
				case 160:
					// unused
					return receive();
				case 128:..case 143:
					if(buffer.length > 7) {
						ubyte[4] _count = buffer[1..4] ~ ubyte(0);
						immutable count = littleEndianToNative!int(_count);
						// send ack
						// id, length (2), unique, from (3), to (3)
						this.socket.sendTo([ubyte(192), ubyte(0), ubyte(1), ubyte(true)] ~ _count, this.address);
						// handle packet
						size_t index = 4;
						immutable info = buffer[index++];
						index += 2; // length / 8
						if((info & 0x7F) >= 64) {
							index += 3; // message index
							if((info & 0x7F) >= 96) {
								index += 3; // order index
								index += 1; // order channel
							}
						}
						if(info & 0x10) {
							if(index + 10 < buffer.length && this.acceptSplit) {
								return this.handleSplit(peek!uint(buffer, &index), peek!ushort(buffer, &index), peek!uint(buffer, &index), buffer[index..$]);
							}
						} else {
							return buffer[index..$];
						}
					}
					break;
				default:
					break;
			}
		}
		return [];
	}

	private ubyte[] handleSplit(uint count, ushort id, uint order, ubyte[] buffer) {
		auto split = id in this.splits;
		if(split is null) {
			//TODO limit count
			this.splits[id].length = count;
			split = id in this.splits;
		}
		if(count == (*split).length && order < count) {
			(*split)[order] = buffer;
			if(++this.splitsCount[id] == count) {
				ubyte[] ret;
				foreach(b ; *split) {
					ret ~= b.dup;
				}
				this.splits.remove(id);
				this.splitsCount.remove(id);
				return ret;
			}
		}
		return [];
	}
	
}
