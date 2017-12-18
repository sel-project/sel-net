﻿/*
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
module sel.net.raknet;

import core.atomic : atomicOp;

import std.algorithm : min;
import std.bitmanip : littleEndianToNative, nativeToLittleEndian, nativeToBigEndian, peek;
import std.conv : to;
import std.math : ceil;
import std.socket : Address, Socket;

import sel.net.stream : Stream;

//debug import std.stdio : writeln;

class RaknetStream : Stream {
	
	private Address address;
	public immutable size_t mtu;

	public bool acceptSplit = true;
	private ubyte[][][ushort] splits;
	private size_t[ushort] splitsCount;
	
	private ubyte[] buffer;
	
	private shared int send_count = -1;
	private ushort split_id = 0;

	private ubyte[][int] sent;
	
	public this(Socket socket, Address address, size_t mtu) {
		super(socket);
		this.address = address;
		this.mtu = mtu;
		this.buffer = new ubyte[mtu + 128];
	}

	public override ptrdiff_t send(ubyte[] _buffer) {
		if(_buffer.length > this.mtu) {
			size_t sent = 0;
			immutable count = to!uint(ceil(_buffer.length.to!float / this.mtu));
			immutable sizes = to!uint(ceil(_buffer.length.to!float / count));
			foreach(order ; 0..count) {
				immutable c = atomicOp!"+="(this.send_count, 1);
				ubyte[] current = _buffer[order*sizes..min((order+1)*sizes, $)];
				ubyte[] _count = nativeToLittleEndian(c)[0..3];
				ubyte[] buffer = [ubyte(140)];
				buffer ~= _count;
				buffer ~= ubyte(64 | 16); // info
				buffer ~= nativeToBigEndian(cast(ushort)(current.length * 8));
				buffer ~= _count; // message index
				buffer ~= nativeToBigEndian(count);
				buffer ~= nativeToBigEndian(this.split_id);
				buffer ~= nativeToBigEndian(order);
				buffer ~= current;
				sent += this.socket.sendTo(buffer, this.address);
				this.sent[c] = buffer;
			}
			this.split_id++;
			return sent;
		} else {
			immutable c = atomicOp!"+="(this.send_count, 1);
			ubyte[] count = nativeToLittleEndian(c)[0..3];
			ubyte[] buffer = [ubyte(132)];
			buffer ~= count;
			buffer ~= ubyte(64); // info
			buffer ~= nativeToBigEndian(cast(ushort)(_buffer.length * 8));
			buffer ~= count; // message index
			buffer ~= _buffer;
			this.sent[c] = buffer;
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
					//writeln("ack: ", getAck(buffer[1..$]));
					foreach(ack ; getAck(buffer[1..$])) {
						this.sent.remove(ack);
					}
					//return receive();
					break;
				case 160:
					int[] nacks = getAck(buffer[1..$]);
					size_t count = 0;
					foreach(nack ; nacks) {
						auto sent = nack in this.sent;
						if(sent) {
							this.socket.sendTo(*sent, this.address);
							//if(++count == 32_000) break;
						}
					}
					//writeln("sent ", nacks.length, " nacks");
					//return receive();
					break;
				case 128:..case 143:
					if(buffer.length > 7) {
						ubyte[4] _count = buffer[1..4] ~ ubyte(0);
						immutable count = littleEndianToNative!int(_count);
						// send ack
						// id, length (2), unique, from (3), to (3)
						this.socket.sendTo([ubyte(192), ubyte(0), ubyte(1), ubyte(true)] ~ buffer[1..4], this.address);
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

int readTriad(ubyte[] data) {
	ubyte[4] bytes = data ~ ubyte(0);
	return littleEndianToNative!int(bytes);
}

int[] getAck(ubyte[] buffer) {
	int[] ret;
	size_t index = 1;
	foreach(i ; 0..buffer[index++]) {
		if(buffer[index++]) {
			ret ~= readTriad(buffer[index..index+=3]);
		} else {
			foreach(num ; readTriad(buffer[index..index+=3])..readTriad(buffer[index..index+=3])+1) {
				ret ~= num;
			}
		}
	}
	return ret;
}