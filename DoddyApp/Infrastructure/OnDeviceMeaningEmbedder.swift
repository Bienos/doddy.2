import DoddyCore
import Foundation
@preconcurrency import NaturalLanguage

/// Meaning-search vectors from Apple's on-device language model (ADR-228). The only file that uses
/// NaturalLanguage (guard script). Note text is processed on the iPhone and never sent anywhere.
///
/// `NLContextualEmbedding` for the Latin script covers Polish and English in one model, so a
/// question and a note in either language land in the same space. It gives one vector per token;
/// the note's vector is their average. If iOS hasn't downloaded the model yet, it is requested
/// once from Apple (a system download of the model only; no note text is sent). Until it is
/// available every call throws `modelUnavailable` and recall uses word search alone.
actor OnDeviceMeaningEmbedder: TextEmbedder {
    nonisolated let modelID: String
    private let embedding: NLContextualEmbedding
    private var isLoaded = false
    private var assetsRequested = false

    init?() {
        guard let embedding = NLContextualEmbedding(script: .latin) else { return nil }
        self.embedding = embedding
        self.modelID = "apple.nlcontextual.\(embedding.modelIdentifier).r\(embedding.revision).mean-v1"
    }

    func embed(_ text: String) async throws -> [Float] {
        try await prepare()
        do {
            return try average(text)
        } catch MeaningSearchError.emptyVector {
            throw MeaningSearchError.emptyVector
        } catch {
            // Too long for the model's sequence limit, or another model refusal: try the start only.
            return try average(String(text.prefix(300)))
        }
    }

    private func prepare() async throws {
        if isLoaded { return }
        if !embedding.hasAvailableAssets {
            guard !assetsRequested else { throw MeaningSearchError.modelUnavailable }
            assetsRequested = true
            let available: Bool = await withCheckedContinuation { continuation in
                embedding.requestAssets { result, _ in continuation.resume(returning: result == .available) }
            }
            guard available else { throw MeaningSearchError.modelUnavailable }
        }
        do {
            try embedding.load()
        } catch {
            throw MeaningSearchError.modelUnavailable
        }
        isLoaded = true
    }

    private func average(_ text: String) throws -> [Float] {
        let result = try embedding.embeddingResult(for: text, language: nil)
        var sum = [Double](repeating: 0, count: embedding.dimension)
        var tokens = 0
        result.enumerateTokenVectors(in: result.string.startIndex..<result.string.endIndex) { vector, _ in
            guard vector.count == sum.count else { return true }
            for index in vector.indices { sum[index] += vector[index] }
            tokens += 1
            return true
        }
        guard tokens > 0 else { throw MeaningSearchError.emptyVector }
        return sum.map { Float($0 / Double(tokens)) }
    }
}
