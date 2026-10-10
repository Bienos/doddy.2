// Stand-in for Apple's ActivityKit so the Live Activity's content type can be type-checked and
// tested on Linux (scripts/check_island_art.sh). Only the one protocol the shared files use.
public protocol ActivityAttributes: Decodable, Encodable {
    associatedtype ContentState: Decodable, Encodable, Hashable
}
