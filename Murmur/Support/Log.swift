import os

enum Log {
    static let app = Logger(subsystem: "dev.harryday.murmur", category: "app")
    static let recording = Logger(subsystem: "dev.harryday.murmur", category: "recording")
    static let ai = Logger(subsystem: "dev.harryday.murmur", category: "ai")
    static let output = Logger(subsystem: "dev.harryday.murmur", category: "output")
}
