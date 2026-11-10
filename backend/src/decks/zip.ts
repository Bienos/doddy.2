import { deflateRawSync, inflateRawSync } from "node:zlib";

/**
 * A minimal ZIP writer for the decks Doddy makes (decision 2026-11-10-better-presentations): an
 * Office file is a ZIP of XML parts. No dependency; deflate comes from Node's zlib. Names are
 * UTF-8 (flag bit 11), there are no directories, comments or ZIP64 (a deck is far below 4 GB).
 */

export interface ZipEntry {
  path: string;
  data: Buffer;
  /** Already compressed (JPEG, PNG): stored as it is. */
  store?: boolean;
}

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

export function crc32(data: Buffer): number {
  let crc = 0xffffffff;
  for (const byte of data) crc = CRC_TABLE[(crc ^ byte) & 0xff]! ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

/** 1 Jan 2026, 00:00 in MS-DOS form: a fixed stamp, so the same deck gives the same bytes. */
const DOS_TIME = 0;
const DOS_DATE = ((2026 - 1980) << 9) | (1 << 5) | 1;

export function zip(entries: ZipEntry[]): Buffer {
  const seen = new Set<string>();
  const locals: Buffer[] = [];
  const centrals: Buffer[] = [];
  let offset = 0;
  for (const entry of entries) {
    if (!entry.path || entry.path.startsWith("/") || entry.path.includes("..") || seen.has(entry.path)) {
      throw new Error("bad zip entry name");
    }
    seen.add(entry.path);
    const name = Buffer.from(entry.path, "utf8");
    const method = entry.store ? 0 : 8;
    const body = entry.store ? entry.data : deflateRawSync(entry.data, { level: 9 });
    const crc = crc32(entry.data);

    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4); // version needed
    local.writeUInt16LE(0x0800, 6); // UTF-8 names
    local.writeUInt16LE(method, 8);
    local.writeUInt16LE(DOS_TIME, 10);
    local.writeUInt16LE(DOS_DATE, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(body.length, 18);
    local.writeUInt32LE(entry.data.length, 22);
    local.writeUInt16LE(name.length, 26);
    local.writeUInt16LE(0, 28);
    locals.push(local, name, body);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4); // made by
    central.writeUInt16LE(20, 6); // needed
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(method, 10);
    central.writeUInt16LE(DOS_TIME, 12);
    central.writeUInt16LE(DOS_DATE, 14);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(body.length, 20);
    central.writeUInt32LE(entry.data.length, 24);
    central.writeUInt16LE(name.length, 28);
    // extra, comment, disk, internal and external attributes: 0
    central.writeUInt32LE(offset, 42);
    centrals.push(central, name);

    offset += local.length + name.length + body.length;
  }
  const directory = Buffer.concat(centrals);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(directory.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, directory, end]);
}

/**
 * Every entry of a plain ZIP (stored or deflated), read through its central directory: for the
 * deck's own read-back check and for tests. Throws on anything else.
 */
export function unzip(file: Buffer): Map<string, Buffer> {
  const endAt = file.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
  if (endAt < 0) throw new Error("not a zip");
  const count = file.readUInt16LE(endAt + 10);
  let at = file.readUInt32LE(endAt + 16);
  const out = new Map<string, Buffer>();
  for (let i = 0; i < count; i++) {
    if (file.readUInt32LE(at) !== 0x02014b50) throw new Error("bad central directory");
    const method = file.readUInt16LE(at + 10);
    const crc = file.readUInt32LE(at + 16);
    const size = file.readUInt32LE(at + 20);
    const nameLength = file.readUInt16LE(at + 28);
    const extra = file.readUInt16LE(at + 30);
    const comment = file.readUInt16LE(at + 32);
    const localAt = file.readUInt32LE(at + 42);
    const name = file.subarray(at + 46, at + 46 + nameLength).toString("utf8");
    if (file.readUInt32LE(localAt) !== 0x04034b50) throw new Error("bad local header");
    const start = localAt + 30 + file.readUInt16LE(localAt + 26) + file.readUInt16LE(localAt + 28);
    const raw = file.subarray(start, start + size);
    const data = method === 0 ? Buffer.from(raw) : method === 8 ? inflateRawSync(raw) : null;
    if (!data || crc32(data) !== crc) throw new Error("bad zip entry");
    out.set(name, data);
    at += 46 + nameLength + extra + comment;
  }
  return out;
}
