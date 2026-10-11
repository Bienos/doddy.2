import DoddyCore
import Foundation
import NaturalLanguage

/// Sentence vectors from Apple's on-device contextual embedding model (ADR-227), the mean of its
/// token vectors. One model per writing system (Latin covers Polish, English, German and the rest),
/// so notes and questions in different Latin-script languages can still meet. The model may be
/// downloaded from Apple once (`requestAssets`); no note or question text leaves the iPhone.
actor OnDeviceEmbedder: MeaningEmbedder {
    private var models: [String: NLContextualEmbedding] = [:]

    func vector(for text: String) async -> [Float]? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let language = recognizer.dominantLanguage ?? .english
        guard let model = await model(for: language) else { return nil }
        guard let result = try? model.embeddingResult(for: text, language: language) else { return nil }
        var sum = [Double](repeating: 0, count: model.dimension)
        var count = 0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            for index in sum.indices where index < vector.count { sum[index] += vector[index] }
            count += 1
            return true
        }
        guard count > 0 else { return nil }
        return sum.map { Float($0 / Double(count)) }
    }

    private func model(for language: NLLanguage) async -> NLContextualEmbedding? {
        guard let model = NLContextualEmbedding(language: language) else { return nil }
        if let loaded = models[model.modelIdentifier] { return loaded }
        if !model.hasAvailableAssets {
            _ = try? await model.requestAssets()
            guard model.hasAvailableAssets else { return nil }
        }
        guard (try? model.load()) != nil else { return nil }
        models[model.modelIdentifier] = model
        return model
    }
}

/// One index for the app, so note vectors are reused between searches.
enum MeaningService {
    static let index = MeaningIndex(embedder: OnDeviceEmbedder())
}
