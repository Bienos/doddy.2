import SwiftUI

// Xcode canvas previews of every Doddy picture and motion in the app (ADR-336), so a Mac check of
// ADR-299 to ADR-331 takes minutes. Made-up content only; nothing here runs in the app.

#Preview("Whole Doddy: every pose") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 16) {
            ForEach(IslandPose.allCases, id: \.self) { pose in
                VStack(spacing: 6) {
                    WholeDoddyView(pose: pose, height: 110)
                    Text(pose.rawValue).font(.caption2)
                }
            }
        }
        .padding()
    }
}

#Preview("Doddy moving: every strip") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 16) {
            ForEach(DoddyMotion.allCases, id: \.self) { motion in
                VStack(spacing: 6) {
                    DoddyMotionView(motion: motion, height: 110)
                    Text(motion.rawValue).font(.caption2)
                }
            }
        }
        .padding()
    }
}

#Preview("Voice screen art") {
    let shown: [VoiceScreenArt] = [.motion(.walk), .pose(.listening), .pose(.kneelingInspect), .talking,
                                   .motion(.run), .pose(.reachingHigh), .pose(.shush), .pose(.fistpump), .pose(.facepalm)]
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 16) {
            ForEach(shown, id: \.self) { art in
                VoiceDoddyView(art: art)
            }
        }
        .padding()
    }
}

#Preview("Scenery strips") {
    let places: [SceneryBackdrop.Place] = [.home, .memory, .coffee, .court, .rooftop]
    ScrollView {
        VStack(spacing: 24) {
            ForEach(places, id: \.self) { place in
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.rawValue).font(.caption)
                    SceneryBackdrop(place: place, height: 120, pose: place == .court ? .basketballDribble : .crosslegged)
                }
            }
        }
        .padding(.vertical)
    }
}

#Preview("Storybook") {
    StorybookView(played: .constant(false))
        .padding()
}

#Preview("Problem with Doddy") {
    VStack(spacing: 16) {
        ProblemView(message: "Couldn't save this note. Nothing was changed, so you can try again.", showsDoddy: true)
        ProblemView(message: "A small inline problem, without Doddy.")
    }
    .padding()
}

#Preview("List share card") {
    ListShareCardView(card: ListShareCard(name: "Shopping", items: ["Oat milk", "Eggs", "Sourdough bread", "Tomatoes"],
                                          showsDoddy: true))
}

#Preview("Siri snippet poses") {
    VStack {
        SiriDoddySnippet(pose: .listening)
        SiriDoddySnippet(pose: .shrug)
    }
}
